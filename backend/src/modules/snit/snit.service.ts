import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Canton } from './canton.entity';

@Injectable()
export class SnitService {
  constructor(
    @InjectRepository(Canton)
    private readonly cantonRepo: Repository<Canton>,
  ) {}

  async findAll(): Promise<any> {
    const cantones = await this.cantonRepo
      .createQueryBuilder('c')
      .select([
        'c.codigo AS codigo',
        'c.nombre AS nombre',
        'c.poblacion AS poblacion',
        'c.fuente AS fuente',
        'c.fecha_obtencion AS fecha_obtencion',
        'ST_AsGeoJSON(c.geom) AS geom',
      ])
      .getRawMany();

    return {
      type: 'FeatureCollection',
      features: cantones.map((c) => ({
        type: 'Feature',
        properties: {
          codigo: c.codigo,
          nombre: c.nombre,
          poblacion: c.poblacion,
          fuente: c.fuente,
          fecha_obtencion: c.fecha_obtencion,
        },
        geometry: c.geom ? JSON.parse(c.geom) : null,
      })),
    };
  }

  async findOne(codigo: string): Promise<any> {
    const canton = await this.cantonRepo
      .createQueryBuilder('c')
      .select([
        'c.codigo AS codigo',
        'c.nombre AS nombre',
        'c.poblacion AS poblacion',
        'c.fuente AS fuente',
        'c.fecha_obtencion AS fecha_obtencion',
        'ST_AsGeoJSON(c.geom) AS geom',
      ])
      .where('c.codigo = :codigo', { codigo })
      .getRawOne();

    if (!canton) return null;

    return {
      type: 'Feature',
      properties: {
        codigo: canton.codigo,
        nombre: canton.nombre,
        poblacion: canton.poblacion,
        fuente: canton.fuente,
        fecha_obtencion: canton.fecha_obtencion,
      },
      geometry: canton.geom ? JSON.parse(canton.geom) : null,
    };
  }
}
