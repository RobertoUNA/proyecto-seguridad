import { Entity, PrimaryGeneratedColumn, Column } from 'typeorm';

@Entity('canton')
export class Canton {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'varchar', length: 20, unique: true })
  codigo: string;

  @Column({ type: 'varchar', length: 100 })
  nombre: string;

  @Column({ type: 'int', nullable: true })
  poblacion: number;

  @Column({ type: 'text' })
  geom: string;

  @Column({ type: 'varchar', length: 50, default: 'SNIT/ArcGIS' })
  fuente: string;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  fecha_obtencion: Date;
}
