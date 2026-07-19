import {
  createContext,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

import { mergeTokens, type TenantBranding, type ThemeTokens } from './tokens';

type ThemeContextValue = {
  /** Tokens ativos: template padrão (teal-clean) ou já sobrepostos pela marca do tenant. */
  tokens: ThemeTokens;
  /**
   * Alimenta a marca do tenant lida do banco (org_branding) após o login.
   * Passe os overrides parciais — internamente são fundidos sobre o template.
   * Passe null para voltar ao default (ex.: logout).
   */
  setTenantBranding: (branding: TenantBranding | null) => void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({
  children,
  tenant = null,
}: {
  children: ReactNode;
  /** Override inicial da marca (ex.: branding pré-carregado). Depois use setTenantBranding(). */
  tenant?: TenantBranding | null;
}) {
  const [branding, setBranding] = useState<TenantBranding | null>(tenant);

  const value = useMemo<ThemeContextValue>(
    () => ({
      tokens: mergeTokens(branding),
      setTenantBranding: setBranding,
    }),
    [branding],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error('useTheme deve ser usado dentro de <ThemeProvider>');
  }
  return ctx;
}
