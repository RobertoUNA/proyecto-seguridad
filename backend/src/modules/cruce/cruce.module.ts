import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Canton } from '../snit/canton.entity';
import { Delito } from '../oij/delito.entity';
import { Accidente } from '../cosevi/accidente.entity';
import { Infraestructura } from '../osm/infraestructura.entity';
import { CruceService } from './cruce.service';
import { CruceController } from './cruce.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Canton, Delito, Accidente, Infraestructura])],
  controllers: [CruceController],
  providers: [CruceService],
})
export class CruceModule {}
