/**
 * Identidade jurídica da empresa responsável pelo Educaty e pelo Programa de Afiliados.
 *
 * FONTE ÚNICA — importe daqui em vez de repetir razão social/CNPJ pelo código.
 * Use nos lugares que precisarem identificar o responsável: Termos do afiliado,
 * Política de Privacidade, futuros recibos/contratos/NF, rodapé, etc.
 */
export const COMPANY = {
  /** Razão social exatamente como consta na Receita Federal. */
  legalName: "N3 COMERCIO E NEGOCIOS DIGITAIS LTDA",
  /** CNPJ formatado. */
  cnpj: "67.796.449/0001-89",
  /** Nome curto / marca da holding. Sempre "N3 Labz" — "N3" sozinho é a marca incompleta. */
  shortName: "N3 Labz",
  /** Produto ao qual estes termos se referem. */
  product: "Educaty",
  /** Endereço da sede (identificação do controlador de dados na LGPD). */
  address:
    "Av. Dr. Franco da Rocha, 607, Vila Zanela, Franco da Rocha/SP, CEP 07851-000",
  /** Contato geral / assuntos de privacidade. Confirmar o e-mail/domínio do produto. */
  email: "contato@educaty.app",
} as const;
