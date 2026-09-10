import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn } from 'typeorm';
import { Canton } from '../snit/canton.entity';

@Entity('delito')
export class Delito {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'int', nullable: true })
  canton_id: number;

  @ManyToOne(() => Canton, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'canton_id' })
  canton: Canton;

  @Column({ type: 'varchar', length: 50, nullable: true })
  provincia: string;

  @Column({ type: 'varchar', length: 100, nullable: true })
  distrito: string;

  @Column({ type: 'varchar', length: 100 })
  tipo: string;

  @Column({ type: 'varchar', length: 150, nullable: true })
  modalidad: string;

  @Column({ type: 'date' })
  fecha: Date;

  @Column({ type: 'int', default: 1 })
  cantidad: number;

  @Column({ type: 'varchar', length: 50, default: 'OIJ/CKAN' })
  fuente: string;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  fecha_obtencion: Date;
}