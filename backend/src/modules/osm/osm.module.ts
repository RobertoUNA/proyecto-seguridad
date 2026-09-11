import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Canton } from '../snit/canton.entity';
import { Infraestructura } from './infraestructura.entity';
import { OsmController } from './osm.controller';
import { OsmService } from './osm.service';

@Module({
  imports: [TypeOrmModule.forFeature([Infraestructura, Canton])],
  controllers: [OsmController],
  providers: [OsmService],
  exports: [OsmService],
})
export class OsmModule {}
