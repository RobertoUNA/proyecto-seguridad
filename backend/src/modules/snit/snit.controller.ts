import { Controller, Get, Param, Res, HttpStatus, NotFoundException } from '@nestjs/common';
import { Response } from 'express';
import { SnitService } from './snit.service';

@Controller('cantones')
export class SnitController {
  constructor(private readonly snitService: SnitService) {}

  @Get()
  async findAll(@Res() res: Response) {
    const data = await this.snitService.findAll();
    res.set('X-Data-Source', 'SNIT/ArcGIS');
    res.set('X-Fetch-Date', new Date().toISOString());
    return res.status(HttpStatus.OK).json(data);
  }

  @Get(':codigo')
  async findOne(@Param('codigo') codigo: string, @Res() res: Response) {
    const data = await this.snitService.findOne(codigo);
    if (!data) {
      return res.status(HttpStatus.NOT_FOUND).json({
        statusCode: 404,
        message: `Cantón con código ${codigo} no encontrado`,
      });
    }
    res.set('X-Data-Source', 'SNIT/ArcGIS');
    res.set('X-Fetch-Date', new Date().toISOString());
    return res.status(HttpStatus.OK).json(data);
  }
}
