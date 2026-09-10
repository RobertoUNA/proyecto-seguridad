import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Brackets } from 'typeorm';
import { Delito } from './delito.entity';
import { Canton } from '../snit/canton.entity';

export interface DelitoFiltros {
  canton?: string;
  tipo?: string;
  modalidad?: string;
  desde?: string;
  hasta?: string;
}

@Injectable()
export class OijService {
  constructor(
    @InjectRepository(Delito)
    private readonly delitoRepo: Repository<Delito>,
    @InjectRepository(Canton)
    private readonly cantonRepo: Repository<Canton>,
  ) {}

  private validarFechas(f: DelitoFiltros): void {
    const desde = f.desde ? new Date(f.desde) : null;
    const hasta = f.hasta ? new Date(f.hasta) : null;
    if (f.desde && (!desde || isNaN(desde.getTime()))) {
      throw new BadRequestException(`Fecha 'desde' inválida: ${f.desde}`);
    }
    if (f.hasta && (!hasta || isNaN(hasta.getTime()))) {
      throw new BadRequestException(`Fecha 'hasta' inválida: ${f.hasta}`);
    }
    if (desde && hasta && desde > hasta) {
      throw new BadRequestException(`'desde' (${f.desde}) no puede ser mayor que 'hasta' (${f.hasta})`);
    }
  }

  private async resolverCanton(value: string): Promise<Canton | null> {
    const buscado = value.trim();
    const candidato = await this.cantonRepo
      .createQueryBuilder('c')
      .select(['c.id', 'c.codigo', 'c.nombre', 'c.fuente', 'c.fecha_obtencion'])
      .where('c.codigo = :codigo', { codigo: buscado })
      .orWhere('UPPER(REPLACE(c.nombre, \' \', \'\')) = UPPER(REPLACE(:nombre, \' \', \'\'))', {
        nombre: buscado,
      })
      .getOne();
    return candidato || null;
  }

  private async construirQuery(f: DelitoFiltros) {
    const qb = this.delitoRepo
      .createQueryBuilder('d')
      .select([
        'd.id',
        'd.canton_id',
        'd.provincia',
        'd.distrito',
        'd.tipo',
        'd.modalidad',
        'd.fecha',
        'd.cantidad',
        'd.fuente',
        'd.fecha_obtencion',
      ]);

    if (f.canton) {
      const canton = await this.resolverCanton(f.canton);
      if (!canton) {
        throw new BadRequestException(`Cantón no encontrado: ${f.canton}`);
      }
      qb.andWhere('d.canton_id = :cantonId', { cantonId: canton.id });
    }
    if (f.tipo) {
      const tipo = f.tipo.toUpperCase();
      qb.andWhere(
        new Brackets((sub) => {
          sub.where('UPPER(d.tipo) LIKE :tipo', { tipo: `%${tipo}%` });
          sub.orWhere('UPPER(d.modalidad) LIKE :tipo', { tipo: `%${tipo}%` });
        }),
      );
    }
    if (f.desde) {
      qb.andWhere('d.fecha >= :desde', { desde: f.desde });
    }
    if (f.hasta) {
      qb.andWhere('d.fecha <= :hasta', { hasta: f.hasta });
    }

    qb.orderBy('d.fecha', 'DESC').addOrderBy('d.cantidad', 'DESC');
    return qb;
  }

  async findAll(f: DelitoFiltros): Promise<any> {
    this.validarFechas(f);
    const qb = await this.construirQuery(f);
    qb.limit(1000);

    const delitos = await qb.getMany();
    const totales = await this.resumenPorCanton(f);

    return {
      delitos,
      totales,
      resumen: {
        registro_cantidad: delitos.reduce((acc, d) => acc + d.cantidad, 0),
      },
      fuente: 'OIJ/CKAN',
      descripcion_fuente: 'Poder Judicial de Costa Rica — Datos Abiertos (Estadísticas Policiales)',
      fecha_obtencion: delitos[0]?.fecha_obtencion ?? null,
    };
  }

  async resumenPorCanton(f: DelitoFiltros): Promise<any> {
    const qb = this.delitoRepo
      .createQueryBuilder('d')
      .select('d.canton_id', 'canton_id')
      .addSelect('SUM(d.cantidad)', 'total')
      .addSelect('COUNT(DISTINCT d.tipo)', 'tipos_distintos')
      .groupBy('d.canton_id');

    if (f.canton) {
      const canton = await this.resolverCanton(f.canton);
      if (canton) {
        qb.andWhere('d.canton_id = :cantonId', { cantonId: canton.id });
      }
    }
    if (f.tipo) {
      const tipo = f.tipo.toUpperCase();
      qb.andWhere(
        new Brackets((sub) => {
          sub.where('UPPER(d.tipo) LIKE :tipo', { tipo: `%${tipo}%` });
          sub.orWhere('UPPER(d.modalidad) LIKE :tipo', { tipo: `%${tipo}%` });
        }),
      );
    }
    if (f.desde) {
      qb.andWhere('d.fecha >= :desde', { desde: f.desde });
    }
    if (f.hasta) {
      qb.andWhere('d.fecha <= :hasta', { hasta: f.hasta });
    }

    const filas = await qb.getRawMany();
    const filtroCanton = f.canton
      ? await this.resolverCanton(f.canton)
      : null;

    const features = await Promise.all(
      filas.map(async (r) => {
        const canton = r.canton_id
          ? await this.cantonRepo
              .createQueryBuilder('c')
              .select([
                'c.codigo AS codigo',
                'c.nombre AS nombre',
                'ST_AsGeoJSON(c.geom) AS geom',
              ])
              .where('c.id = :id', { id: r.canton_id })
              .getRawOne()
          : null;
        return {
          type: 'Feature',
          properties: {
            codigo: canton?.codigo ?? null,
            nombre: canton?.nombre ?? 'Sin cantón asignado',
            total_delitos: Number(r.total),
            tipos_distintos: Number(r.tipos_distintos),
          },
          geometry: canton?.geom ? JSON.parse(canton.geom) : null,
          aplica_filtro_canton: !!filtroCanton,
        };
      }),
    );

    return { type: 'FeatureCollection', features };
  }

  async listarTipos(): Promise<string[]> {
    const filas = await this.delitoRepo
      .createQueryBuilder('d')
      .select('DISTINCT d.tipo', 'tipo')
      .orderBy('tipo', 'ASC')
      .getRawMany();
    return filas.map((r) => r.tipo);
  }
}