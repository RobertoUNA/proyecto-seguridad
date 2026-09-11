import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Canton } from '../snit/canton.entity';
import { Delito } from '../oij/delito.entity';
import { Accidente } from '../cosevi/accidente.entity';
import { Infraestructura } from '../osm/infraestructura.entity';

interface DelitosFila {
  canton_id: string;
  total: string;
  tipos_distintos: string;
  fecha_obtencion: Date | null;
}

interface AccidentesFila {
  canton_id: string;
  total: string;
  clases_distintas: string;
  fecha_obtencion: Date | null;
}

interface InfraestructuraFila {
  canton_id: string;
  total: string;
  hospitales: string;
  clinicas: string;
  comisarias: string;
  fecha_obtencion: Date | null;
}

interface AgregadoCanton {
  totalDelitos: number;
  tiposDistintos: number;
  delitosFecha: Date | null;
  totalAccidentes: number;
  clasesDistintas: number;
  accidentesFecha: Date | null;
  totalInfraestructura: number;
  hospitales: number;
  clinicas: number;
  comisarias: number;
  infraestructuraFecha: Date | null;
  score: number;
}

@Injectable()
export class CruceService {
  constructor(
    @InjectRepository(Canton)
    private readonly cantonRepo: Repository<Canton>,
    @InjectRepository(Delito)
    private readonly delitoRepo: Repository<Delito>,
    @InjectRepository(Accidente)
    private readonly accidenteRepo: Repository<Accidente>,
    @InjectRepository(Infraestructura)
    private readonly infraestructuraRepo: Repository<Infraestructura>,
  ) {}

  private async resolverCanton(value: string): Promise<Canton | null> {
    const buscado = value.trim();
    return this.cantonRepo
      .createQueryBuilder('c')
      .select(['c.id', 'c.codigo', 'c.nombre', 'c.poblacion', 'c.fuente', 'c.fecha_obtencion'])
      .where('c.codigo = :codigo', { codigo: buscado })
      .orWhere('UPPER(REPLACE(c.nombre, \' \', \'\')) = UPPER(REPLACE(:nombre, \' \', \'\'))', {
        nombre: buscado,
      })
      .getOne();
  }

  // Agrega las 3 fuentes por cantón para TODOS los cantones a la vez (una
  // consulta agrupada por fuente, no una por cantón). Se necesita el
  // universo completo porque el índice que se expone es un percentil: la
  // posición relativa de un cantón frente a los demás, no un valor absoluto.
  private async agregarPorCanton(): Promise<Map<number, AgregadoCanton>> {
    const [cantonIds, delitosFilas, accidentesFilas, infraestructuraFilas] = await Promise.all([
      this.cantonRepo.createQueryBuilder('c').select('c.id', 'id').getRawMany<{ id: string }>(),
      this.delitoRepo
        .createQueryBuilder('d')
        .select('d.canton_id', 'canton_id')
        .addSelect('SUM(d.cantidad)', 'total')
        .addSelect('COUNT(DISTINCT d.tipo)', 'tipos_distintos')
        .addSelect('MAX(d.fecha_obtencion)', 'fecha_obtencion')
        .where('d.canton_id IS NOT NULL')
        .groupBy('d.canton_id')
        .getRawMany<DelitosFila>(),
      this.accidenteRepo
        .createQueryBuilder('a')
        .select('a.canton_id', 'canton_id')
        .addSelect('SUM(a.cantidad)', 'total')
        .addSelect('COUNT(DISTINCT a.clase)', 'clases_distintas')
        .addSelect('MAX(a.fecha_obtencion)', 'fecha_obtencion')
        .where('a.canton_id IS NOT NULL')
        .groupBy('a.canton_id')
        .getRawMany<AccidentesFila>(),
      this.infraestructuraRepo
        .createQueryBuilder('i')
        .select('i.canton_id', 'canton_id')
        .addSelect('COUNT(*)', 'total')
        .addSelect("COUNT(*) FILTER (WHERE i.tipo = 'hospital')", 'hospitales')
        .addSelect("COUNT(*) FILTER (WHERE i.tipo = 'clinica')", 'clinicas')
        .addSelect("COUNT(*) FILTER (WHERE i.tipo = 'comisaria')", 'comisarias')
        .addSelect('MAX(i.fecha_obtencion)', 'fecha_obtencion')
        .where('i.canton_id IS NOT NULL')
        .groupBy('i.canton_id')
        .getRawMany<InfraestructuraFila>(),
    ]);

    const delitosMap = new Map(delitosFilas.map((f) => [Number(f.canton_id), f]));
    const accidentesMap = new Map(accidentesFilas.map((f) => [Number(f.canton_id), f]));
    const infraestructuraMap = new Map(infraestructuraFilas.map((f) => [Number(f.canton_id), f]));

    const agregados = new Map<number, AgregadoCanton>();
    for (const { id } of cantonIds) {
      const cantonId = Number(id);
      const d = delitosMap.get(cantonId);
      const a = accidentesMap.get(cantonId);
      const i = infraestructuraMap.get(cantonId);

      const totalDelitos = Number(d?.total ?? 0);
      const totalAccidentes = Number(a?.total ?? 0);
      const totalInfraestructura = Number(i?.total ?? 0);

      agregados.set(cantonId, {
        totalDelitos,
        tiposDistintos: Number(d?.tipos_distintos ?? 0),
        delitosFecha: d?.fecha_obtencion ?? null,
        totalAccidentes,
        clasesDistintas: Number(a?.clases_distintas ?? 0),
        accidentesFecha: a?.fecha_obtencion ?? null,
        totalInfraestructura,
        hospitales: Number(i?.hospitales ?? 0),
        clinicas: Number(i?.clinicas ?? 0),
        comisarias: Number(i?.comisarias ?? 0),
        infraestructuraFecha: i?.fecha_obtencion ?? null,
        // Ratio bruto sin acotar: a más delitos/accidentes y menos
        // infraestructura, más alto. El +1 evita dividir entre cero.
        score: (totalDelitos + totalAccidentes) / (1 + totalInfraestructura),
      });
    }
    return agregados;
  }

  // Percentil (0-100) del cantón frente a todos los demás: 100 = el más
  // vulnerable del país (más incidentes, menos infraestructura relativa),
  // 0 = el mejor cubierto. A diferencia del ratio bruto (sin techo), esto
  // sí es comparable entre cantones de distinto tamaño de forma legible.
  private calcularPercentil(agregados: Map<number, AgregadoCanton>, cantonId: number): number {
    const scores = [...agregados.values()].map((a) => a.score);
    const propio = agregados.get(cantonId)?.score ?? 0;
    if (scores.length <= 1) return 0;
    const menoresOIguales = scores.filter((s) => s <= propio).length;
    return Math.round((menoresOIguales / scores.length) * 100);
  }

  async panorama(id: string): Promise<Record<string, unknown>> {
    const canton = await this.resolverCanton(id);
    if (!canton) {
      throw new NotFoundException(`Cantón no encontrado: ${id}`);
    }

    const [geo, agregados] = await Promise.all([
      this.cantonRepo
        .createQueryBuilder('c')
        .select('ST_AsGeoJSON(c.geom)', 'geom')
        .where('c.id = :id', { id: canton.id })
        .getRawOne<{ geom: string | null }>(),
      this.agregarPorCanton(),
    ]);

    const propio = agregados.get(canton.id);
    const percentil = this.calcularPercentil(agregados, canton.id);

    return {
      type: 'Feature',
      properties: {
        codigo: canton.codigo,
        nombre: canton.nombre,
        poblacion: canton.poblacion,
        delitos: {
          total: propio?.totalDelitos ?? 0,
          tipos_distintos: propio?.tiposDistintos ?? 0,
          fuente: 'OIJ/CKAN',
          fecha_obtencion: propio?.delitosFecha ?? null,
        },
        accidentes: {
          total: propio?.totalAccidentes ?? 0,
          clases_distintas: propio?.clasesDistintas ?? 0,
          fuente: 'COSEVI',
          fecha_obtencion: propio?.accidentesFecha ?? null,
        },
        infraestructura: {
          total: propio?.totalInfraestructura ?? 0,
          hospitales: propio?.hospitales ?? 0,
          clinicas: propio?.clinicas ?? 0,
          comisarias: propio?.comisarias ?? 0,
          fuente: 'OSM/Overpass',
          fecha_obtencion: propio?.infraestructuraFecha ?? null,
        },
        // 0-100: percentil de vulnerabilidad frente a todos los cantones.
        indice_cobertura: percentil,
        // Ratio bruto sin acotar, por transparencia de cómo se llegó al percentil.
        indice_cobertura_ratio: Number((propio?.score ?? 0).toFixed(2)),
        indice_cobertura_formula:
          'Percentil (0-100) del ratio (delitos + accidentes) / (1 + infraestructura) frente a todos los cantones del país: 100 = el más vulnerable, 0 = el mejor cubierto.',
      },
      geometry: geo?.geom ? JSON.parse(geo.geom) : null,
    };
  }
}
