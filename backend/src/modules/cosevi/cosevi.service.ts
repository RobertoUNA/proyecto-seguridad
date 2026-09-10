import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Brackets, SelectQueryBuilder, Repository } from 'typeorm';
import { Canton } from '../snit/canton.entity';
import { Accidente } from './accidente.entity';

export interface AccidenteFiltros {
  canton?: string;
  anio?: string;
  clase?: string;
  tipo?: string;
}

@Injectable()
export class CoseviService {
  constructor(
    @InjectRepository(Accidente)
    private readonly accidenteRepo: Repository<Accidente>,
    @InjectRepository(Canton)
    private readonly cantonRepo: Repository<Canton>,
  ) {}

  private validarFiltros(filtros: AccidenteFiltros): void {
    if (!filtros.anio) return;
    const anio = Number(filtros.anio);
    if (!Number.isInteger(anio) || anio < 1900 || anio > 2100) {
      throw new BadRequestException(`Año inválido: ${filtros.anio}`);
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
    query: SelectQueryBuilder<Accidente>,
    filtros: AccidenteFiltros,
  ): Promise<void> {
    if (filtros.canton) {
      const canton = await this.resolverCanton(filtros.canton);
      if (!canton) throw new BadRequestException(`Cantón no encontrado: ${filtros.canton}`);
      query.andWhere('a.canton_id = :cantonId', { cantonId: canton.id });
    }
    if (filtros.anio) query.andWhere('a.anio = :anio', { anio: Number(filtros.anio) });
    if (filtros.clase) {
      query.andWhere('UPPER(a.clase) LIKE :clase', { clase: `%${filtros.clase.toUpperCase()}%` });
    }
    if (filtros.tipo) {
      query.andWhere(
        new Brackets((sub) => {
          sub.where('UPPER(a.tipo) LIKE :tipo', { tipo: `%${filtros.tipo!.toUpperCase()}%` });
          sub.orWhere('UPPER(a.clase) LIKE :tipo', { tipo: `%${filtros.tipo!.toUpperCase()}%` });
        }),
      );
    }
  }

  async findAll(filtros: AccidenteFiltros): Promise<Record<string, unknown>> {
    this.validarFiltros(filtros);
    const query = this.accidenteRepo.createQueryBuilder('a').orderBy('a.anio', 'DESC').addOrderBy('a.cantidad', 'DESC');
    await this.aplicarFiltros(query, filtros);
    const accidentes = await query.take(1000).getMany();
    const totales = await this.resumenPorCanton(filtros);

    return {
      accidentes,
      totales,
      resumen: {
        registro_cantidad: accidentes.reduce((total, accidente) => total + accidente.cantidad, 0),
      },
      fuente: 'COSEVI',
      descripcion_fuente: 'Consejo de Seguridad Vial — accidentes de tránsito con víctimas',
      fecha_obtencion: accidentes[0]?.fecha_obtencion ?? null,
    };
  }

  async resumenPorCanton(filtros: AccidenteFiltros): Promise<Record<string, unknown>> {
    this.validarFiltros(filtros);
    const query = this.accidenteRepo
      .createQueryBuilder('a')
      .leftJoin(Canton, 'c', 'c.id = a.canton_id')
      .select('a.canton_id', 'canton_id')
      .addSelect('c.codigo', 'codigo')
      .addSelect('c.nombre', 'nombre')
      .addSelect('ST_AsGeoJSON(c.geom)', 'geom')
      .addSelect('SUM(a.cantidad)', 'total_accidentes')
      .addSelect('COUNT(DISTINCT a.clase)', 'clases_distintas')
      .addSelect('COUNT(DISTINCT a.tipo)', 'tipos_distintos')
      .groupBy('a.canton_id')
      .addGroupBy('c.codigo')
      .addGroupBy('c.nombre')
      .addGroupBy('c.geom');
    await this.aplicarFiltros(query, filtros);

    const rows = await query.getRawMany<{
      canton_id: string | null;
      codigo: string | null;
      nombre: string | null;
      geom: string | null;
      total_accidentes: string;
      clases_distintas: string;
      tipos_distintos: string;
    }>();

    return {
      type: 'FeatureCollection',
      features: rows.map((row) => ({
        type: 'Feature',
        properties: {
          codigo: row.codigo,
          nombre: row.nombre ?? 'Sin cantón asignado',
          total_accidentes: Number(row.total_accidentes),
          clases_distintas: Number(row.clases_distintas),
          tipos_distintos: Number(row.tipos_distintos),
        },
        geometry: row.geom ? JSON.parse(row.geom) : null,
      })),
    };
  }

  async listarTipos(): Promise<string[]> {
    const rows = await this.accidenteRepo
      .createQueryBuilder('a')
      .select('DISTINCT a.tipo', 'tipo')
      .orderBy('tipo', 'ASC')
      .getRawMany<{ tipo: string }>();
    return rows.map((row) => row.tipo);
  }

  async listarClases(): Promise<string[]> {
    const rows = await this.accidenteRepo
      .createQueryBuilder('a')
      .select('DISTINCT a.clase', 'clase')
      .orderBy('clase', 'ASC')
      .getRawMany<{ clase: string }>();
    return rows.map((row) => row.clase);
  }
}
