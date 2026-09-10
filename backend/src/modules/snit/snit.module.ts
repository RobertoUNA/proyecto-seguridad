import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Canton } from './canton.entity';
import { SnitService } from './snit.service';
import { SnitController } from './snit.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Canton])],
  controllers: [SnitController],
  providers: [SnitService],
})
export class SnitModule {}
