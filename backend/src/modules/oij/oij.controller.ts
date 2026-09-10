import { Controller, Get, Query, Res, HttpStatus } from '@nestjs/common';
import { Response } from 'express';
import { OijService, DelitoFiltros } from './oij.service';

@Controller('delitos')
export class OijController {
  constructor(private readonly oijService: OijService) {}

  @Get()
  async findAll(@Query() filtros: DelitoFiltros, @Res() res: Response) {
    const data = await this.oijService.findAll(filtros);
    res.set('X-Data-Source', 'OIJ/CKAN');
    res.set('X-Fetch-Date', new Date().toISOString());
    return res.status(HttpStatus.OK).json(data);
  }

  @Get('por-canton')
  async resumenPorCanton(@Query() filtros: DelitoFiltros, @Res() res: Response) {
    const data = await this.oijService.resumenPorCanton(filtros);
    res.set('X-Data-Source', 'OIJ/CKAN');
    return res.status(HttpStatus.OK).json(data);
  }

  @Get('tipos')
  async listarTipos(@Res() res: Response) {
    const data = await this.oijService.listarTipos();
    return res.status(HttpStatus.OK).json({ tipos: data, fuente: 'OIJ/CKAN' });
  }
}