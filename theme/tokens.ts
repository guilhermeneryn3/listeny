/**
 * Contrato de tokens do tema — MESMAS chaves do backend (theme_templates / org_branding,
 * ver supabase/migrations/0003_branding.sql) e do portal web. A "cara" do tenant é DADO,
 * não código: estes defaults (template "teal-clean") valem até o app ler o branding do
 * tenant no login e sobrepor via ThemeProvider (tenant override).
 *
 * NUNCA hardcode cor/raio/fonte na tela — leia sempre de useTheme().tokens.
 */
export type ThemeTokens = {
  primary: string;
  primaryDark: string;
  bg: string;
  surface: string;
  ink: string;
  sub: string;
  hint: string;
  edge: string;
  soft: string;
  success: string;
  warn: string;
  danger: string;
  tint: string;
  /** Raio base da marca, em px. No banco pode vir como "16px" (string) — normalizado ao fundir. */
  radius: number;
  /** Família tipográfica da marca (ex.: "Plus Jakarta Sans"). Carregada sob demanda. */
  font: string;
};

/** Chave de cada token (útil pra validar overrides parciais vindos do banco). */
export type ThemeTokenKey = keyof ThemeTokens;

/**
 * Template padrão "teal-clean" — espelha o seed de theme_templates em 0003_branding.sql.
 * radius aqui é number (16); no banco o mesmo valor aparece como "16px".
 */
export const defaultTokens: ThemeTokens = {
  primary: '#14B8A6',
  primaryDark: '#0D9488',
  bg: '#F7F8FA',
  surface: '#FFFFFF',
  ink: '#17181D',
  sub: '#5A6172',
  hint: '#9AA0AB',
  edge: '#ECECF2',
  soft: '#F1F3F7',
  success: '#16A34A',
  warn: '#B45309',
  danger: '#F0473C',
  tint: '#ECFDF9',
  radius: 16,
  font: 'Plus Jakarta Sans',
};

/**
 * Overrides parciais da marca do tenant (org_branding.palette = jsonb parcial). Aplicados
 * por cima do template. Aceita um subconjunto das chaves; radius pode chegar como "16px".
 */
export type TenantBranding = Partial<Omit<ThemeTokens, 'radius'>> & {
  radius?: number | string;
};

/** Normaliza o radius, que pode vir como "16px" (banco) ou 16 (number). */
function toRadius(value: number | string | undefined, fallback: number): number {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const parsed = parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

/**
 * Funde os overrides do tenant sobre os defaults, produzindo tokens completos.
 * É AQUI que a marca lida do banco (org_branding) entra no app.
 */
export function mergeTokens(tenant?: TenantBranding | null): ThemeTokens {
  if (!tenant) return defaultTokens;
  return {
    ...defaultTokens,
    ...tenant,
    radius: toRadius(tenant.radius, defaultTokens.radius),
  };
}
