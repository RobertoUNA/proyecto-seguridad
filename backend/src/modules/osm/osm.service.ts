import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, SelectQueryBuilder } from 'typeorm';
import { Canton } from '../snit/canton.entity';
import { Infraestructura } from './infraestructura.entity';

export interface InfraestructuraFiltros {
  canton?: string;
  tipo?: string;
}

const TIPOS_VALIDOS = ['hospital', 'clinica', 'comisaria'];

@Injectable()
export class OsmService {
  constructor(
    @InjectRepository(Infraestructura)
    private readonly infraestructuraRepo: Repository<Infraestructura>,
    @InjectRepository(Canton)
    private readonly cantonRepo: Repository<Canton>,
  ) {}

  private validarFiltros(filtros: InfraestructuraFiltros): void {
    if (filtros.tipo && !TIPOS_VALIDOS.includes(filtros.tipo.toLowerCase())) {
      throw new BadRequestException(
        `Tipo inválido: ${filtros.tipo}. Valores permitidos: ${TIPOS_VALIDOS.join(', ')}`,
      );
    }
  }

  private async resolverCanton(value: string): Promise<Canton | null> {
    const buscado = value.trim();
    return this.cantonRepo
      .createQueryBuilder('c')
      .where('c.codigo = :codigo', { codigo: buscado })
      .orWhere('UPPER(REPLACE(c.nombre, \' \', \'\')) = UPPER(REPLACE(:nombre, \' \', \'\'))', {
        nombre: buscado,
      })
      .getOne();
  }

  private async aplicarFiltros(
    query: SelectQueryBuilder<Infraestructura>,
    filtros: InfraestructuraFiltros,
  ): Promise<void> {
    if (filtros.canton) {
      const canton = await this.resolverCanton(filtros.canton);
      if (!canton) throw new BadRequestException(`Cantón no encontrado: ${filtros.canton}`);
      query.andWhere('i.canton_id = :cantonId', { cantonId: canton.id });
    }
    if (filtros.tipo) {
      query.andWhere('i.tipo = :tipo', { tipo: filtros.tipo.toLowerCase() });
    }
  }

  async findAll(filtros: InfraestructuraFiltros): Promise<Record<string, unknown>> {
    this.validarFiltros(filtros);
    const query = this.infraestructuraRepo
      .createQueryBuilder('i')
      .orderBy('i.tipo', 'ASC')
      .addOrderBy('i.nombre', 'ASC');
    await this.aplicarFiltros(query, filtros);
    // A diferencia de delitos/accidentes (series temporales donde 1000 es
    // "los más recientes"), infraestructura es un snapshot nacional acotado.
    // Ordenar por tipo ASC + take(1000) dejaba fuera comisaria/hospital
    // porque "clinica" (1124 registros) agota el límite alfabéticamente.
    const registros = await query.take(5000).getMany();

    return {
      infraestructura: registros,
      resumen: {
        registro_cantidad: registros.length,
      },
      fuente: 'OSM/Overpass',
      descripcion_fuente: 'OpenStreetMap vía Overpass API — hospitales, clínicas y comisarías',
      fecha_obtencion: registros[0]?.fecha_obtencion ?? null,
    };
  }

  async resumenPorCanton(filtros: InfraestructuraFiltros): Promise<Record<string, unknown>> {
    this.validarFiltros(filtros);
    const query = this.infraestructuraRepo
      .createQueryBuilder('i')
      .leftJoin(Canton, 'c', 'c.id = i.canton_id')
      .select('i.canton_id', 'canton_id')
      .addSelect('c.codigo', 'codigo')
      .addSelect('c.nombre', 'nombre')
      .addSelect('ST_AsGeoJSON(c.geom)', 'geom')
      .addSelect('COUNT(*)', 'total_infraestructura')
      .addSelect("COUNT(*) FILTER (WHERE i.tipo = 'hospital')", 'hospitales')
      .addSelect("COUNT(*) FILTER (WHERE i.tipo = 'clinica')", 'clinicas')
      .addSelect("COUNT(*) FILTER (WHERE i.tipo = 'comisaria')", 'comisarias')
      .groupBy('i.canton_id')
      .addGroupBy('c.codigo')
      .addGroupBy('c.nombre')
      .addGroupBy('c.geom');
    await this.aplicarFiltros(query, filtros);

    const rows = await query.getRawMany<{
      canton_id: string | null;
      codigo: string | null;
      nombre: string | null;
      geom: string | null;
      total_infraestructura: string;
      hospitales: string;
      clinicas: string;
      comisarias: string;
    }>();

    return {
      type: 'FeatureCollection',
      features: rows.map((row) => ({
        type: 'Feature',
        properties: {
          codigo: row.codigo,
          nombre: row.nombre ?? 'Sin cantón asignado',
          total_infraestructura: Number(row.total_infraestructura),
          hospitales: Number(row.hospitales),
          clinicas: Number(row.clinicas),
          comisarias: Number(row.comisarias),
        },
        geometry: row.geom ? JSON.parse(row.geom) : null,
      })),
    };
  }
}
