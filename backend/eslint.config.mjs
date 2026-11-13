import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist/**', 'coverage/**', 'node_modules/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    // Los 4 `any` existentes (oij.service, snit.service) se reportan como aviso,
    // no como error, para no tocar codigo de otros modulos antes de la entrega.
    rules: { '@typescript-eslint/no-explicit-any': 'warn' },
  },
);
