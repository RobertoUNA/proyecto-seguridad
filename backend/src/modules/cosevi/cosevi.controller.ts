import { Controller, Get, HttpStatus, Query, Res } from '@nestjs/common';
import { Response } from 'express';
import { AccidenteFiltros, CoseviService } from './cosevi.service';

@Controller('accidentes')
export class CoseviController {
  constructor(private readonly coseviService: CoseviService) {}

  @Get()
  async findAll(@Query() filtros: AccidenteFiltros, @Res() res: Response) {
    const data = await this.coseviService.findAll(filtros);
    res.set('X-Data-Source', 'COSEVI');
    return res.status(HttpStatus.OK).json(data);
  }

  @Get('por-canton')
  async resumenPorCanton(@Query() filtros: AccidenteFiltros, @Res() res: Response) {
    const data = await this.coseviService.resumenPorCanton(filtros);
    res.set('X-Data-Source', 'COSEVI');
    return res.status(HttpStatus.OK).json(data);
  }

  @Get('tipos')
  async listarTipos(@Res() res: Response) {
    const tipos = await this.coseviService.listarTipos();
    return res.status(HttpStatus.OK).json({ tipos, fuente: 'COSEVI' });
  }

  @Get('clases')
  async listarClases(@Res() res: Response) {
    const clases = await this.coseviService.listarClases();
    return res.status(HttpStatus.OK).json({ clases, fuente: 'COSEVI' });
  }
}
