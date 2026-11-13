import { NotFoundException } from '@nestjs/common';
import { CruceService } from './cruce.service';

// Repositorio falso: createQueryBuilder devuelve un builder encadenable cuyos
// metodos terminales (getOne / getRawOne / getRawMany) devuelven datos fijos.
function repoFalso(datos: { getOne?: unknown; getRawOne?: unknown; getRawMany?: unknown[] }) {
  const qb: Record<string, jest.Mock> = {};
  for (const m of ['select', 'addSelect', 'where', 'orWhere', 'groupBy']) {
    qb[m] = jest.fn().mockReturnValue(qb);
  }
  qb.getOne = jest.fn().mockResolvedValue(datos.getOne ?? null);
  qb.getRawOne = jest.fn().mockResolvedValue(datos.getRawOne ?? null);
  qb.getRawMany = jest.fn().mockResolvedValue(datos.getRawMany ?? []);
  return { createQueryBuilder: jest.fn().mockReturnValue(qb), qb };
}

interface Escenario {
  cantones: { id: number; codigo: string; nombre: string }[];
  delitos?: { canton_id: number; total: number }[];
  accidentes?: { canton_id: number; total: number }[];
  infraestructura?: { canton_id: number; total: number }[];
  geom?: string | null;
}

function crearServicio(e: Escenario, buscado: number | null) {
  const cantonEncontrado = e.cantones.find((c) => c.id === buscado) ?? null;
  const canton = repoFalso({
    getOne: cantonEncontrado && { ...cantonEncontrado, poblacion: 1000 },
    getRawOne: { geom: e.geom ?? null },
    getRawMany: e.cantones.map((c) => ({ id: String(c.id) })),
  });
  const delito = repoFalso({
    getRawMany: (e.delitos ?? []).map((d) => ({
      canton_id: String(d.canton_id),
      total: String(d.total),
      tipos_distintos: '1',
      fecha_obtencion: null,
    })),
  });
  const accidente = repoFalso({
    getRawMany: (e.accidentes ?? []).map((a) => ({
      canton_id: String(a.canton_id),
      total: String(a.total),
      clases_distintas: '1',
      fecha_obtencion: null,
    })),
  });
  const infra = repoFalso({
    getRawMany: (e.infraestructura ?? []).map((i) => ({
      canton_id: String(i.canton_id),
      total: String(i.total),
      hospitales: '0',
      clinicas: '0',
      comisarias: '0',
      fecha_obtencion: null,
    })),
  });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const service = new CruceService(canton as any, delito as any, accidente as any, infra as any);
  return { service, canton };
}

const tres = [
  { id: 1, codigo: '101', nombre: 'San Jose' },
  { id: 2, codigo: '102', nombre: 'Escazu' },
  { id: 3, codigo: '103', nombre: 'Desamparados' },
];

type Props = { indice_cobertura: number; indice_cobertura_ratio: number };
const props = (r: Record<string, unknown>) => r.properties as Props;

describe('CruceService.panorama - indice_cobertura', () => {
  it('caso normal: percentil relativo entre cantones y ratio bruto', async () => {
    // scores: c1 = (10+5)/(1+2) = 5 ; c2 = 2/(1+0) = 2 ; c3 = 0/(1+4) = 0
    const escenario: Escenario = {
      cantones: tres,
      delitos: [
        { canton_id: 1, total: 10 },
        { canton_id: 2, total: 2 },
      ],
      accidentes: [{ canton_id: 1, total: 5 }],
      infraestructura: [
        { canton_id: 1, total: 2 },
        { canton_id: 3, total: 4 },
      ],
    };
    const esperado: [number, number, number][] = [
      [1, 100, 5],
      [2, 67, 2],
      [3, 33, 0],
    ];
    for (const [id, percentil, ratio] of esperado) {
      const { service } = crearServicio(escenario, id);
      const r = props(await service.panorama(String(id)));
      expect(r.indice_cobertura).toBe(percentil);
      expect(r.indice_cobertura_ratio).toBe(ratio);
    }
  });

  it('limite: canton con 0 infraestructura no divide entre cero', async () => {
    const { service } = crearServicio(
      { cantones: tres, delitos: [{ canton_id: 2, total: 7 }] },
      2,
    );
    const r = props(await service.panorama('102'));
    expect(Number.isFinite(r.indice_cobertura_ratio)).toBe(true);
    expect(r.indice_cobertura_ratio).toBe(7);
  });

  it('limite: canton con 0 delitos y 0 accidentes tiene ratio 0', async () => {
    const { service } = crearServicio(
      { cantones: tres, delitos: [{ canton_id: 1, total: 3 }] },
      3,
    );
    const r = props(await service.panorama('103'));
    expect(r.indice_cobertura_ratio).toBe(0);
  });

  it('limite: canton unico devuelve percentil 0', async () => {
    const { service } = crearServicio(
      { cantones: [tres[0]], delitos: [{ canton_id: 1, total: 50 }] },
      1,
    );
    const r = props(await service.panorama('101'));
    expect(r.indice_cobertura).toBe(0);
  });

  it('limite: cantones con score empatado comparten percentil 100', async () => {
    const { service } = crearServicio(
      {
        cantones: [tres[0], tres[1]],
        delitos: [
          { canton_id: 1, total: 4 },
          { canton_id: 2, total: 4 },
        ],
      },
      1,
    );
    const r = props(await service.panorama('101'));
    expect(r.indice_cobertura).toBe(100);
  });

  it('error: canton inexistente lanza NotFoundException', async () => {
    const { service } = crearServicio({ cantones: tres }, null);
    await expect(service.panorama('999')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('el identificador se recorta antes de buscarlo (parametro con espacios)', async () => {
    const { service, canton } = crearServicio({ cantones: tres }, 1);
    await service.panorama('  101  ');
    expect(canton.qb.where).toHaveBeenCalledWith('c.codigo = :codigo', { codigo: '101' });
  });

  it('geometry es null si el canton no tiene geom', async () => {
    const { service } = crearServicio({ cantones: tres, geom: null }, 1);
    const r = await service.panorama('101');
    expect(r.geometry).toBeNull();
  });
});
