import type {ICookieCategory, IOptions, ITextResources} from 'consent-banner'
import {privacyPolicyUrl, cookieInventoryUrl, docsURL, themes, CookieCategoryId} from './configuration'

const CookieCategoryName = {
  Required: '必須',
  Analytics: '分析',
  SocialMedia: 'ソーシャル メディア',
  Advertising: '広告',
} as const

export const cookieCategories: ICookieCategory[] = [
  {
    id: CookieCategoryId.Required,
    name: CookieCategoryName.Required,
    descHtml:
      'GitHub は、必要不可欠なウェブサイト機能を実行し、サービスを提供するために必須 Cookie を使用します。Cookie の使用例には、ログインの実行、言語設定の保存、ショッピング カート エクスペリエンスの提供、パフォーマンスの向上、ウェブ サーバー間のトラフィックのルーティング、画面サイズの検知、ページ読み込み時間の確定、ユーザー エクスペリエンスの改善、およびオーディエンス測定などがあります。これらの Cookie は、GitHub ウェブサイトを機能させるために必要です。.',
    isUnswitchable: true,
  },
  {
    id: CookieCategoryId.Analytics,
    name: CookieCategoryName.Analytics,
    descHtml:
      'GitHub は、分析 Cookie の使用をサードパーティに許可し、GitHub ウェブサイトの使用状況を把握することで、ウェブサイトの改善を図っています。例えば、Cookie はユーザーがアクセスするページや、タスクを完了するために必要なクリック数に関する情報を収集するために使用されます。また、パーソナライズされた広告を提供するためにも分析 Cookie を使用しています。.',
  },
  {
    id: CookieCategoryId.SocialMedia,
    name: CookieCategoryName.SocialMedia,
    descHtml:
      'GitHub とサードパーティは、ユーザーのソーシャル メディア プロファイルと、GitHub ウェブサイトでのアクティビティに基づいた広告とコンテンツを表示するために、ソーシャル メディア Cookie を使用しています。これらの Cookie を使用することで、GitHub ウェブサイトやソーシャル メディアで表示される広告とコンテンツにユーザーの関心がより良く反映されるようになります。これにより、サードパーティは製品の開発および改善も可能になります。これらの製品は、GitHub が所有または運営しないウェブサイトで使用される場合があります。.',
  },
  {
    id: CookieCategoryId.Advertising,
    name: CookieCategoryName.Advertising,
    descHtml:
      '上記に加えて、GitHub とサードパーティは、ユーザーが既に閲覧した広告に基づいて新しい広告を表示するための広告 Cookie も使用しています。Cookie は、ユーザーがクリックする広告や、広告をクリックした後での購入も追跡します。これは、関連性の高い広告の表示、および広告パートナーとの業務上の目的のために行われます。例えば、Cookie はユーザーが広告をクリックしたことを検知し、ソーシャル メディアでの関心やウェブサイトの閲覧履歴に基づいて広告を表示するために使用されます。.',
  },
]

const textResources: ITextResources = {
  bannerMessageHtml: `GitHub は、GitHub ウェブサイトでのユーザー エクスペリエンスを向上させるとともに、オンライン アクティビティに基づいてパーソナライズされた広告を表示するために、オプションの Cookie を使用しています。オプションの Cookie を拒否する場合は、上記のサービスを提供するために必要な Cookie のみが使用されます。許可する Cookie の選択は、ページの最下部にある [Manage Cookies] をクリックすることで変更できます。この選択は 180 日間保持されます。Cookie の選択は定期的に確認するようにしてください。<br/> <br/> <a href="${docsURL}">Cookie 設定の管理方法</a> | <a href="${privacyPolicyUrl}">プライバシー ステートメント</a> | <a href="${cookieInventoryUrl}">サードパーティ Cookie</a>。`,
  acceptAllLabel: '承認',
  rejectAllLabel: '拒否',
  moreInfoLabel: 'Cookieの管理',
  preferencesDialogCloseLabel: '閉じる',
  preferencesDialogTitle: 'Cookie 設定を管理する',
  preferencesDialogDescHtml: `ほとんどの GitHub ウェブサイトでは、Cookie が使用されています。Cookie は、データを保存してウェブ サーバーが後ほど使用できるようにするために、デバイス上に保存される小さなテキストファイルです。GitHub と GitHub のサードパーティ パートナーは、ユーザーの好みや設定の記憶、サインインの簡略化、パーソナライズされた広告の表示、ウェブサイトの機能性を分析するために Cookie を使用します。詳細については、<a href="${privacyPolicyUrl}">プライバシー ステートメント</a>の「Cookie および類似のテクノロジとは?」セクションを参照してください。`,
  acceptLabel: '同意する',
  rejectLabel: '拒否する',
  saveLabel: '変更の保存',
  resetLabel: 'すべてリセット',
}

export const consentControlOptions: IOptions = {
  textResources,
  themes,
  initialTheme: 'github',
}
