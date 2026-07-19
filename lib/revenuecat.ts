import Purchases, { LOG_LEVEL, type CustomerInfo } from 'react-native-purchases';

/** Chave pública do RevenueCat (segura no client). */
const API_KEY = process.env.EXPO_PUBLIC_REVENUECAT_API_KEY ?? '';

/** Um único entitlement pago (`premium`). Casa com o tier no banco. */
export const ENTITLEMENTS = { premium: 'premium' } as const;

export type Tier = 'free' | 'premium';

export const isRevenueCatConfigured = API_KEY.length > 0;

let configured = false;

/**
 * Configura o SDK do RevenueCat uma única vez. `appUserID` amarra a conta do
 * RevenueCat ao usuário do Supabase (quando já logado); anônimo caso contrário.
 * Stub da Fase 0 — trocar por chaves por plataforma (goog_/appl_) no lançamento.
 */
export function configureRevenueCat(appUserId?: string | null): void {
  if (!isRevenueCatConfigured || configured) return;
  // O RevenueCat FECHA o app ao detectar chave de teste (test_) num build de release.
  // Nesse caso não configuramos: o app roda sem compras (tier free) em vez de crashar.
  if (!__DEV__ && API_KEY.startsWith('test_')) {
    console.warn('[revenuecat] chave de teste em build release — SDK não configurado (compras off).');
    return;
  }
  Purchases.setLogLevel(__DEV__ ? LOG_LEVEL.WARN : LOG_LEVEL.ERROR);
  Purchases.configure({ apiKey: API_KEY, appUserID: appUserId ?? undefined });
  configured = true;
}

/** Deriva o plano a partir do CustomerInfo: tem o entitlement `premium` → premium, senão free. */
export function tierFrom(info: CustomerInfo | null): Tier {
  const active = info?.entitlements.active ?? {};
  if (active[ENTITLEMENTS.premium]) return 'premium';
  return 'free';
}
