import { Controller, Get, HttpStatus, Query, Res } from '@nestjs/common';
import { Response } from 'express';
import { InfraestructuraFiltros, OsmService } from './osm.service';

@Controller('infraestructura')
export class OsmController {
  constructor(private readonly osmService: OsmService) {}

  @Get()
  async findAll(@Query() filtros: InfraestructuraFiltros, @Res() res: Response) {
    const data = await this.osmService.findAll(filtros);
    res.set('X-Data-Source', 'OSM/Overpass');
    res.set('X-Fetch-Date', new Date().toISOString());
    return res.status(HttpStatus.OK).json(data);
  }

  @Get('por-canton')
  async resumenPorCanton(@Query() filtros: InfraestructuraFiltros, @Res() res: Response) {
    const data = await this.osmService.resumenPorCanton(filtros);
    res.set('X-Data-Source', 'OSM/Overpass');
    res.set('X-Fetch-Date', new Date().toISOString());
    return res.status(HttpStatus.OK).json(data);
  }
}
