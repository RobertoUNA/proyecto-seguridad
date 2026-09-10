import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Delito } from './delito.entity';
import { Canton } from '../snit/canton.entity';
import { OijService } from './oij.service';
import { OijController } from './oij.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Delito, Canton])],
  controllers: [OijController],
  providers: [OijService],
  exports: [OijService],
})
export class OijModule {}