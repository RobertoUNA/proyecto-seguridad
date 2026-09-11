import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SnitModule } from './modules/snit/snit.module';
import { OijModule } from './modules/oij/oij.module';
import { CoseviModule } from './modules/cosevi/cosevi.module';
import { OsmModule } from './modules/osm/osm.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env', '.env.local'],
    }),
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432', 10) || 5432,
      username: process.env.DB_USER || 'seguridad_vial',
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME || 'seguridad_vial_db',
      autoLoadEntities: true,
      synchronize: false,
    }),
    SnitModule,
    OijModule,
    CoseviModule,
    OsmModule,
  ],
})
export class AppModule {}
