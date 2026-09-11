import { Column, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn } from 'typeorm';
import { Canton } from '../snit/canton.entity';

@Entity('infraestructura')
export class Infraestructura {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'varchar', length: 10 })
  osm_type: string;

  @Column({ type: 'bigint' })
  osm_id: string;

  @Column({ type: 'int', nullable: true })
  canton_id: number | null;

  @ManyToOne(() => Canton, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'canton_id' })
  canton: Canton | null;

  @Column({ type: 'varchar', length: 50, nullable: true })
  provincia: string | null;

  @Column({ type: 'varchar', length: 100, nullable: true })
  distrito: string | null;

  @Column({ type: 'varchar', length: 200, nullable: true })
  nombre: string | null;

  @Column({ type: 'varchar', length: 50 })
  tipo: string;

  @Column({ type: 'double precision' })
  lat: number;

  @Column({ type: 'double precision' })
  lon: number;

  @Column({ type: 'varchar', length: 50, default: 'OSM/Overpass' })
  fuente: string;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  fecha_obtencion: Date;
}
