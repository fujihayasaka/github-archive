import type {ICookieCategory, IOptions, ITextResources} from 'consent-banner'
import {privacyPolicyUrl, cookieInventoryUrl, docsURL, themes, CookieCategoryId} from './configuration'

const CookieCategoryName = {
  Required: 'Requerido',
  Analytics: 'Analíticas',
  SocialMedia: 'Redes sociales',
  Advertising: 'Publicidad',
} as const

export const cookieCategories: ICookieCategory[] = [
  {
    id: CookieCategoryId.Required,
    name: CookieCategoryName.Required,
    descHtml:
      'GitHub utiliza las cookies necesarias para ejecutar las funciones esenciales del sitio web y prestar los servicios. Por ejemplo, las cookies se utilizan para iniciar sesión, guardar tus preferencias de idioma, proporcionar una buena experiencia con el carrito de la compra, mejorar el rendimiento, dirigir el tráfico entre servidores web, detectar el tamaño de la pantalla, determinar los tiempos de carga de la página, mejorar la experiencia del usuario y medir la audiencia. Estas cookies son necesarias para que nuestros sitios web funcionen.',
    isUnswitchable: true,
  },
  {
    id: CookieCategoryId.Analytics,
    name: CookieCategoryName.Analytics,
    descHtml:
      'Permitimos que los terceros utilicen cookies de análisis para comprender cómo utiliza nuestros sitios web y poder mejorarlos. Por ejemplo, las cookies se utilizan para recopilar información sobre las páginas que visita y cuántos clics se necesitan para realizar una tarea. También utilizamos algunas cookies de análisis para ofrecer publicidad personalizada.',
  },
  {
    id: CookieCategoryId.SocialMedia,
    name: CookieCategoryName.SocialMedia,
    descHtml:
      'GitHub y otros terceros utilizan cookies de redes sociales para mostrarte anuncios y contenidos basados en tus perfiles de redes sociales y tu actividad en los sitios web de GitHub. Esto garantiza que los anuncios y contenidos que aparecen en nuestros sitios web y en las redes sociales reflejen mejor tus intereses. Esto también permite a terceros desarrollar y mejorar sus productos, que pueden utilizar en sitios web que no son propiedad ni están gestionados por GitHub.',
  },
  {
    id: CookieCategoryId.Advertising,
    name: CookieCategoryName.Advertising,
    descHtml:
      'Además, GitHub y otros terceros utilizan cookies de publicidad para mostrarte nuevos anuncios basados en los que ya has visto. Las cookies también rastrean los anuncios en los que haces clic o las compras que realizas después de hacer clic en un anuncio. Lo hacemos para mostrarte anuncios que sean más relevantes para ti y con fines comerciales con nuestros socios publicitarios. Por ejemplo, las cookies se utilizan para detectar cuándo haces clic en un anuncio y mostrarte anuncios basados en tus intereses en las redes sociales y en tu historial de navegación por el sitio web.',
  },
]

const textResources: ITextResources = {
  bannerMessageHtml: `Utilizamos cookies opcionales para mejorar tu experiencia en nuestros sitios web y mostrarte publicidad personalizada basada en tu actividad en línea. Si rechazas las cookies opcionales, solo se utilizarán las cookies necesarias para prestarte los servicios indicados anteriormente. Para cambiar la selección de las cookies que deseas aceptar, haz clic en “Administrar cookies” en la parte inferior de la página. Esta selección se mantiene durante 180 días. Revisa tu selección con regularidad. <br/> <br/> <a href="${docsURL}">Cómo gestionar las preferencias de cookies</a> | <a href="${privacyPolicyUrl}">Declaración de privacidad</a> | <a href="${cookieInventoryUrl}">Cookies de terceros</a>.`,
  acceptAllLabel: 'Aceptar',
  rejectAllLabel: 'Rechazar',
  moreInfoLabel: 'Administrar cookies',
  preferencesDialogCloseLabel: 'Cerrar',
  preferencesDialogTitle: 'Gestionar las preferencias de cookies',
  preferencesDialogDescHtml: `La mayoría de los sitios web de GitHub utilizan cookies. Las cookies son pequeños archivos de texto que se almacenan en tu dispositivo para que los servidores web puedan utilizarlos posteriormente. GitHub y nuestros socios terceros utilizan cookies para recordar tus preferencias y configuración, ayudarte a iniciar sesión, mostrarte anuncios personalizados y analizar el funcionamiento de nuestros sitios web. Para obtener más información, consulta la sección Cookies y tecnologías similares de la <a href="${privacyPolicyUrl}">Declaración de privacidad</a>.`,
  acceptLabel: 'Aceptar',
  rejectLabel: 'Rechazar',
  saveLabel: 'Guardar cambios',
  resetLabel: 'Restablecer todas',
}

export const consentControlOptions: IOptions = {
  textResources,
  themes,
  initialTheme: 'github',
}
