import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import { Response } from 'express';
import { HealthService } from './health.service';

@Controller('health')
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get()
  async check(@Res() res: Response) {
    const data = await this.healthService.check();
    res.set('X-Data-Source', 'INTERNAL/HEALTH');
    res.set('X-Fetch-Date', data.fecha_obtencion);
    return res.status(HttpStatus.OK).json(data);
  }
}
