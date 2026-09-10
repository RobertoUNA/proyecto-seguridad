import { Column, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn } from 'typeorm';
import { Canton } from '../snit/canton.entity';

@Entity('accidente')
export class Accidente {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'int', nullable: true })
  canton_id: number | null;

  @ManyToOne(() => Canton, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'canton_id' })
  canton: Canton | null;

  @Column({ type: 'varchar', length: 100, nullable: true })
  canton_nombre: string | null;

  @Column({ type: 'varchar', length: 50, nullable: true })
  provincia: string | null;

  @Column({ type: 'varchar', length: 100, nullable: true })
  distrito: string | null;

  @Column({ type: 'smallint' })
  anio: number;

  @Column({ type: 'varchar', length: 100 })
  clase: string;

  @Column({ type: 'varchar', length: 150 })
  tipo: string;

  @Column({ type: 'int', default: 1 })
  cantidad: number;

  @Column({ type: 'varchar', length: 50, default: 'COSEVI' })
  fuente: string;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  fecha_obtencion: Date;
}
