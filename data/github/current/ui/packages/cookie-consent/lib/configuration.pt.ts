import type {ICookieCategory, IOptions, ITextResources} from 'consent-banner'
import {privacyPolicyUrl, cookieInventoryUrl, CookieCategoryId, docsURL, themes} from './configuration'

const CookieCategoryName = {
  Required: 'Obrigatórios',
  Analytics: 'Analíticos',
  SocialMedia: 'Mídia social',
  Advertising: 'Publicidade',
} as const

export const cookieCategories: ICookieCategory[] = [
  {
    id: CookieCategoryId.Required,
    name: CookieCategoryName.Required,
    descHtml:
      'O GitHub usa cookies obrigatórios para realizar funções essenciais do site e fornecer serviços. Por exemplo, cookies são usados para permitir seu login, salvar suas preferências de idioma, fornecer uma experiência de carrinho de compras, melhorar o desempenho, rotear tráfego entre servidores web, detectar o tamanho da sua tela, determinar tempos de carregamento de páginas, melhorar a experiência de usuário e para medição de público. Esses cookies são necessários para que nossos sites funcionem.',
    isUnswitchable: true,
  },
  {
    id: CookieCategoryId.Analytics,
    name: CookieCategoryName.Analytics,
    descHtml:
      'Permitimos que terceiros usem cookies analíticos para entender como você usa nossos sites para que possamos melhorá-los. Por exemplo, cookies são usados para coletar informações sobre as páginas que você visita e quantos cliques são necessários para concluir uma tarefa. Também usamos cookies analíticos para veicular anúncios personalizados.',
  },
  {
    id: CookieCategoryId.SocialMedia,
    name: CookieCategoryName.SocialMedia,
    descHtml:
      'O GitHub e terceiros usam cookies de mídia social para mostrar anúncios e conteúdo com base em seus perfis de mídia social e atividade em sites do GitHub. Isso garante que os anúncios e o conteúdo que você vê em nossos sites e redes sociais vão estar mais alinhados aos seus interesses. Também permite que terceiros desenvolvam e melhorem seus produtos, que podem ser usados em sites que não são de propriedade ou operados pelo GitHub.',
  },
  {
    id: CookieCategoryId.Advertising,
    name: CookieCategoryName.Advertising,
    descHtml:
      'Além disso, o GitHub e terceiros usam cookies de publicidade para mostrar novos anúncios com base em anúncios que você já viu. Os cookies também rastreiam em quais anúncios você clicou ou compras que realizou após clicar em um anúncio. Isso é feito para veicular os anúncios que são mais relevantes para você e para fins comerciais com nossos parceiros de publicidade. Por exemplo, cookies são usados para detectar quando você clica em um anúncio e para veicular anúncios com base em seus interesses de mídia social e histórico de navegação em sites.',
  },
]

const textResources: ITextResources = {
  bannerMessageHtml: `Usamos cookies opcionais para melhorar sua experiência em nossos sites e para exibir publicidade personalizada com base em sua atividade on-line. Se você rejeitar os cookies opcionais, somente serão usados os cookies necessários para fornecer os serviços listados acima. Você pode alterar sua escolha de quais cookies você aceita ao clicar em “Gerenciar cookies” no parte inferior da página. Essa escolha é mantida por 180 dias. Revise suas escolhas regularmente. <br/> <br/> <a href="${docsURL}">Como gerenciar preferências de cookies</a> | <a href="${privacyPolicyUrl}">Declaração de Privacidade</a> | <a href="${cookieInventoryUrl}">Cookies de terceiros</a>.`,
  acceptAllLabel: 'Aceitar',
  rejectAllLabel: 'Rejeitar',
  moreInfoLabel: 'Gerenciar cookies',
  preferencesDialogCloseLabel: 'Fechar',
  preferencesDialogTitle: 'Gerenciar preferências de cookies',
  preferencesDialogDescHtml: `A maioria dos sites do GitHub usa cookies. Cookies são pequenos arquivos de texto que são colocados em seu dispositivo para armazenar dados para que servidores web possam usá-los posteriormente. O GitHub e nossos parceiros terceiros usam cookies para lembrar de suas preferências e configurações, permitir seu login, veicular anúncios personalizados e analisar o nível de funcionamento de nossos sites. Para obter mais informações, consulte a seção Cookies e tecnologias de rastreamento da <a href="${privacyPolicyUrl}">Declaração de Privacidade</a>.`,
  acceptLabel: 'Aceitar',
  rejectLabel: 'Rejeitar',
  saveLabel: 'Salvar alterações',
  resetLabel: 'Redefinir tudo',
}

export const consentControlOptions: IOptions = {
  textResources,
  themes,
  initialTheme: 'github',
}
