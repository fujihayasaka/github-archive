type FigmaIconProps = React.PropsWithChildren<React.HTMLAttributes<SVGElement>>

export function FigmaIcon({className, ...rest}: FigmaIconProps) {
  return (
    <svg
      aria-label="Figma logo"
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      {...rest}
    >
      <g clipPath="url(#clip0_216_3161)">
        <path
          d="M7.99837 7.99967C7.99837 6.52683 9.1922 5.33301 10.665 5.33301C12.1379 5.33301 13.3317 6.52683 13.3317 7.99967C13.3317 9.47252 12.1379 10.6663 10.665 10.6663C9.1922 10.6663 7.99837 9.47252 7.99837 7.99967Z"
          fill="#1ABCFE"
        />
        <path
          d="M2.66504 13.3337C2.66504 11.8608 3.85886 10.667 5.33171 10.667H7.99837V13.3337C7.99837 14.8065 6.80455 16.0003 5.33171 16.0003C3.85886 16.0003 2.66504 14.8065 2.66504 13.3337Z"
          fill="#0ACF83"
        />
        <path
          d="M7.99837 0V5.33333H10.665C12.1379 5.33333 13.3317 4.13951 13.3317 2.66667C13.3317 1.19382 12.1379 0 10.665 0H7.99837Z"
          fill="#FF7262"
        />
        <path
          d="M2.665 2.66667C2.665 4.13951 3.85883 5.33333 5.33167 5.33333H7.99833V0H5.33167C3.85883 0 2.665 1.19382 2.665 2.66667Z"
          fill="#F24E1E"
        />
        <path
          d="M2.66504 7.99967C2.66504 9.47252 3.85886 10.6663 5.33171 10.6663H7.99837V5.33301H5.33171C3.85886 5.33301 2.66504 6.52683 2.66504 7.99967Z"
          fill="#A259FF"
        />
      </g>
      <defs>
        <clipPath id="clip0_216_3161">
          <rect width="10.6667" height="16" fill="white" transform="translate(2.665)" />
        </clipPath>
      </defs>
    </svg>
  )
}
