import { Controller, Get, Param, Res, HttpStatus } from '@nestjs/common';
import { Response } from 'express';
import { CruceService } from './cruce.service';

@Controller('cantones')
export class CruceController {
  constructor(private readonly cruceService: CruceService) {}

  @Get(':id/panorama')
  async panorama(@Param('id') id: string, @Res() res: Response) {
    const data = await this.cruceService.panorama(id);
    res.set('X-Data-Source', 'SNIT+OIJ+COSEVI+OSM/Overpass');
    res.set('X-Fetch-Date', new Date().toISOString());
    return res.status(HttpStatus.OK).json(data);
  }
}
