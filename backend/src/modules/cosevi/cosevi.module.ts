import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Canton } from '../snit/canton.entity';
import { Accidente } from './accidente.entity';
import { CoseviController } from './cosevi.controller';
import { CoseviService } from './cosevi.service';

@Module({
  imports: [TypeOrmModule.forFeature([Accidente, Canton])],
  controllers: [CoseviController],
  providers: [CoseviService],
  exports: [CoseviService],
})
export class CoseviModule {}
