import type {ICookieCategory, IOptions, ITextResources} from 'consent-banner'
import {privacyPolicyUrl, cookieInventoryUrl, docsURL, themes, CookieCategoryId} from './configuration'

const CookieCategoryName = {
  Required: '필수',
  Analytics: '분석',
  SocialMedia: '소셜 미디어',
  Advertising: '광고',
} as const

export const cookieCategories: ICookieCategory[] = [
  {
    id: CookieCategoryId.Required,
    name: CookieCategoryName.Required,
    descHtml:
      'GitHub는 필수 웹 사이트 기능을 수행하고 서비스를 제공하기 위해 필수 쿠키를 사용합니다. 예를 들어, 쿠키는 로그인, 언어 기본 설정 저장, 장바구니 환경 제공, 성능 개선, 웹 서버 간 트래픽 라우팅, 화면 크기 감지, 페이지 로드 시간 결정, 사용자 경험 개선, 인터넷 방문자 분석 등에 사용됩니다. 이러한 쿠키는 웹 사이트 작동에 필요합니다.',
    isUnswitchable: true,
  },
  {
    id: CookieCategoryId.Analytics,
    name: CookieCategoryName.Analytics,
    descHtml:
      '당사는 타사가 웹 사이트 개선을 위해 사용자가 당사 웹 사이트를 어떻게 사용하는지 파악하는 데 분석 쿠키를 사용하는 것을 허용합니다. 예를 들어, 쿠키는 사용자가 방문한 페이지와 작업을 완료하는 데 필요한 클릭 수에 대한 정보를 수집하는 데 사용됩니다. 맞춤형 광고를 제공하기 위해 일부 분석 쿠키도 사용됩니다.',
  },
  {
    id: CookieCategoryId.SocialMedia,
    name: CookieCategoryName.SocialMedia,
    descHtml:
      'GitHub와 타사는 소셜 미디어 쿠키를 사용하여 사용자의 소셜 미디어 프로필과 GitHub 웹 사이트 활동을 기반으로 광고와 콘텐츠를 표시합니다. 이를 통해 당사 웹 사이트와 소셜 미디어에서 사용자가 보는 광고와 콘텐츠가 사용자의 관심사를 더 잘 반영할 수 있습니다. 또한 이를 통해 타사는 GitHub가 소유하거나 운영하지 않는 웹 사이트에서 사용할 수 있는 제품을 개발하고 개선할 수 있습니다.',
  },
  {
    id: CookieCategoryId.Advertising,
    name: CookieCategoryName.Advertising,
    descHtml:
      'GitHub와 타사는 광고 쿠키를 사용하여 사용자가 이미 본 광고를 기반으로 새로운 광고를 표시합니다. 또한 쿠키는 사용자가 어떤 광고를 클릭했는지 또는 광고 클릭 후 무엇을 구매했는지 추적합니다. 이는 사용자에게 더 관련성이 높은 광고를 표시하고 광고 파트너와의 비즈니스 목적을 위해 수행됩니다. 예를 들어, 쿠키는 사용자가 광고를 클릭하는 시점을 감지하고 소셜 미디어 관심사 및 웹 사이트 검색 기록을 기반으로 광고를 표시하는 데 사용됩니다.',
  },
]

const textResources: ITextResources = {
  bannerMessageHtml: `당사는 선택적 쿠키를 사용하여 웹 사이트 경험을 개선하고 사용자의 온라인 활동을 기반으로 맞춤 광고를 표시합니다. 선택적 쿠키를 거부하면 위에 나열된 서비스를 제공하는 데 필요한 쿠키만 사용됩니다. 페이지 하단의 "쿠키 관리"를 클릭하여 허용할 쿠키에 대한 선택 사항을 변경할 수 있습니다. 이 선택 사항은 180일 동안 유지됩니다. 정기적으로 선택 사항을 검토하십시오.<br/> <br/> <a href="${docsURL}">쿠키 기본 설정 관리 방법</a> | <a href="${privacyPolicyUrl}">개인 정보 보호 정책</a> | <a href="${cookieInventoryUrl}">타사 쿠키</a>`,
  acceptAllLabel: '허용',
  rejectAllLabel: '거부',
  moreInfoLabel: '쿠키 관리',
  preferencesDialogCloseLabel: '닫기',
  preferencesDialogTitle: '쿠키 기본 설정 관리',
  preferencesDialogDescHtml: `대부분의 GitHub 웹 사이트에서 쿠키를 사용합니다. 쿠키는 웹 서버가 나중에 사용할 수 있도록 데이터를 저장하기 위해 사용자 장치에 배치되는 작은 텍스트 파일입니다. GitHub와 타사 파트너는 쿠키를 사용하여 사용자의 기본 설정과 설정을 기억하고, 로그인을 돕고, 맞춤 광고를 표시하고, 웹 사이트가 얼마나 잘 작동하는지 분석합니다. 자세한 내용은 <a href="${privacyPolicyUrl}">개인 정보 보호 정책</a>의 쿠키 및 유사 기술 섹션을 참조하십시오.`,
  acceptLabel: '동의',
  rejectLabel: '거부',
  saveLabel: '변경 사항 저장',
  resetLabel: '모두 재설정',
}

export const consentControlOptions: IOptions = {
  textResources,
  themes,
  initialTheme: 'github',
}
