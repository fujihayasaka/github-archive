interface IconComponentProps {
  size?: number | string
}

export const NodeIcon = ({size = 16}: IconComponentProps = {}) => (
  <svg
    width={size}
    height={size}
    fill="none"
    viewBox="0 0 16 16"
    aria-hidden="true"
    xmlns="http://www.w3.org/2000/svg"
    style={{color: 'var(--fgColor-muted)', display: 'inline-block', verticalAlign: 'text-bottom'}}
  >
    <path
      fill="currentColor"
      fillRule="evenodd"
      d="M.5 6v4.5A2.5 2.5 0 0 0 3 13h1.645a3.5 3.5 0 0 1-.11-1.5H3a1 1 0 0 1-1-1V6zM14 6v4.5a1 1 0 0 1-1 1h-1.535a3.5 3.5 0 0 1-.11 1.5H13a2.5 2.5 0 0 0 2.5-2.5V6zm-4 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0"
      clipRule="evenodd"
    />
    <path
      fill="currentColor"
      fillRule="evenodd"
      d="M15.5 10V5.5A2.5 2.5 0 0 0 13 3h-1.645a3.5 3.5 0 0 1 .11 1.5H13a1 1 0 0 1 1 1V10zM2 10V5.5a1 1 0 0 1 1-1h1.535a3.5 3.5 0 0 1 .11-1.5H3A2.5 2.5 0 0 0 .5 5.5V10zm4-6a2 2 0 1 1 4 0 2 2 0 0 1-4 0"
      clipRule="evenodd"
    />
  </svg>
)

export const ComposeIcon = ({size = 16}: IconComponentProps = {}) => (
  <svg
    width={size}
    height={size}
    fill="none"
    viewBox="0 0 16 16"
    aria-hidden="true"
    xmlns="http://www.w3.org/2000/svg"
    style={{color: 'var(--fgColor-muted', display: 'inline-block', verticalAlign: 'text-bottom'}}
  >
    <path
      fill="currentColor"
      fillRule="evenodd"
      d="M14.515.456a1.555 1.555 0 00-2.2 0L6.58 6.19a1.556 1.556 0 00-.396.673l-.825 2.89a.667.667 0 00.824.824l2.89-.826c.254-.072.485-.209.672-.396l5.735-5.734a1.556 1.556 0 000-2.2l-.965-.965zm-1.257.942a.222.222 0 01.314 0l.965.966a.222.222 0 010 .314L13.415 3.8l-1.28-1.28 1.123-1.122zm-2.065 2.066l1.279 1.279-3.67 3.67a.221.221 0 01-.096.056l-1.736.496.496-1.736c.01-.036.03-.07.057-.096l3.67-3.67zM1.639 4.778a2.25 2.25 0 012.25-2.25h3.154a.75.75 0 000-1.5H3.889a3.75 3.75 0 00-3.75 3.75v7.333a3.75 3.75 0 003.75 3.75h7.333a3.75 3.75 0 003.75-3.75V8.445a.75.75 0 00-1.5 0v3.666a2.25 2.25 0 01-2.25 2.25H3.889a2.25 2.25 0 01-2.25-2.25V4.778z"
      clipRule="evenodd"
    />
  </svg>
)

export const DiceIcon = ({size = 16}: IconComponentProps = {}) => (
  <svg
    width={size}
    height={size}
    fill="none"
    viewBox="0 0 16 16"
    aria-hidden="true"
    xmlns="http://www.w3.org/2000/svg"
    style={{color: 'var(--fgColor-muted', display: 'inline-block', verticalAlign: 'text-bottom'}}
  >
    <path
      fill="currentColor"
      fillRule="evenodd"
      d="M13 .5H3A2.5 2.5 0 0 0 .5 3v10A2.5 2.5 0 0 0 3 15.5h10a2.5 2.5 0 0 0 2.5-2.5V3A2.5 2.5 0 0 0 13 .5M2 3a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1zm6 6.25a1.25 1.25 0 1 0 0-2.5 1.25 1.25 0 0 0 0 2.5M12.25 5a1.25 1.25 0 1 1-2.5 0 1.25 1.25 0 0 1 2.5 0M5 12.25a1.25 1.25 0 1 0 0-2.5 1.25 1.25 0 0 0 0 2.5"
      clipRule="evenodd"
    />
  </svg>
)

export const SpacesIcon = ({size = 16}: IconComponentProps = {}) => (
  <svg
    width={size}
    height={size}
    fill="none"
    viewBox="0 0 16 16"
    aria-hidden="true"
    xmlns="http://www.w3.org/2000/svg"
    style={{color: 'var(--fgColor-muted', display: 'inline-block', verticalAlign: 'text-bottom'}}
  >
    <path
      fillRule="evenodd"
      clipRule="evenodd"
      d="M11.9853 4.76795c.2467 1.23107.1819 2.55631-.3218 3.71134 1.0897-1.00527 1.7464-2.46826 1.7464-3.86921 0-.41421.3357-.75.75-.75.4142 0 .75.33579.75.75 0 2.80515-2.0553 5.92172-5.26314 6.53282.12999.0339.26315.0635.39904.0885 1.3486.2485 2.7916.0174 3.7282-.5446.3552-.2131.8159-.0979 1.029.2573.2131.3552.0979.8159-.2573 1.029-1.3033.782-3.1303 1.0359-4.77168.7335-1.47895-.2726-2.95185-1.0297-3.73462-2.4328.03609.3407.0998.6912.19117 1.0445.39625 1.5319 1.23152 2.7976 2.12066 3.2689.36598.194.5054.6479.31141 1.0139-.19399.366-.64793.5054-1.01391.3114-1.41889-.7521-2.42362-2.4914-2.87037-4.2186-.37219-1.439-.41354-3.09054.18406-4.40236-.18676.13263-.36743.27694-.54001.43237-1.03593.93306-1.73142 2.22122-1.73142 3.69879 0 .4142-.33579.75-.75.75-.41422 0-.75-.3358-.75-.75 0-1.97509.934-3.64826 2.22755-4.81334.88055-.7931 1.9505-1.37217 3.05387-1.65822-.11043-.0376-.22261-.07252-.33631-.10464-1.50098-.42402-2.98649-.28172-3.84609.36302-.33136.24853-.80147.18139-1.05-.14998-.24854-.33136-.1814-.80146.14997-1.05 1.38041-1.03537 3.4149-1.0978 5.1539-.60654 1.67421.47295 3.33259 1.53108 4.06402 3.11319l.0038.00674c.035-.47081.0022-.96424-.0972-1.46029-.2603-1.29954-.95701-2.50156-1.90466-3.21238-.33135-.24854-.39848-.71865-.14994-1.050006.24855-.331356.71865-.398487 1.05001-.14994C10.8023 1.6197 11.6657 3.17263 11.9853 4.76795ZM7.99998 6.0001c-1.10457 0-2 .89543-2 2s.89543 2 2 2 2-.89543 2-2-.89543-2-2-2Z"
      fill="currentColor"
    />
  </svg>
)

export const LoopsIcon = ({size = 16}: IconComponentProps = {}) => (
  <svg
    width={size}
    height={size}
    fill="none"
    viewBox="0 0 16 16"
    aria-hidden="true"
    xmlns="http://www.w3.org/2000/svg"
    style={{color: 'var(--fgColor-muted', display: 'inline-block', verticalAlign: 'text-bottom'}}
  >
    <path
      fillRule="evenodd"
      clipRule="evenodd"
      fill="currentColor"
      d="M8 6.984c.59-.533 1.204-1.066 1.825-1.493.797-.548 1.7-.991 2.675-.991C14.414 4.5 16 6.086 16 8s-1.586 3.5-3.5 3.5c-.975 0-1.878-.444-2.675-.991-.621-.427-1.235-.96-1.825-1.493-.59.533-1.204 1.066-1.825 1.493-.797.547-1.7.991-2.675.991C1.586 11.5 0 9.914 0 8s1.586-3.5 3.5-3.5c.975 0 1.878.443 2.675.991.621.427 1.235.96 1.825 1.493ZM9.114 8c.536.483 1.052.922 1.56 1.273.704.483 1.3.727 1.826.727 1.086 0 2-.914 2-2 0-1.086-.914-2-2-2-.525 0-1.122.244-1.825.727-.51.35-1.025.79-1.561 1.273ZM3.5 6c-1.086 0-2 .914-2 2 0 1.086.914 2 2 2 .525 0 1.122-.244 1.825-.727.51-.35 1.025-.79 1.561-1.273-.536-.483-1.052-.922-1.56-1.273C4.621 6.244 4.025 6 3.5 6Z"
    />
  </svg>
)

export const iconMapping = {
  compose: ComposeIcon,
  dice: DiceIcon,
  loops: LoopsIcon,
  node: NodeIcon,
  spaces: SpacesIcon,
}

export type IconName = keyof typeof iconMapping
