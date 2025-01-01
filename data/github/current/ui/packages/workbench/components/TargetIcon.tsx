import type {Icon} from '@primer/octicons-react'

export const TargetIcon: Icon = props => {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" {...props}>
      <g clipPath="url(#clip0_1934_35984)">
        <path
          d="M8 0a.75.75 0 01.75.75v.793a6.503 6.503 0 015.707 5.707h.793a.75.75 0 110 1.5h-.793a6.503 6.503 0 01-5.707 5.707v.793a.75.75 0 11-1.5 0v-.793A6.503 6.503 0 011.543 8.75H.75a.75.75 0 010-1.5h.793A6.503 6.503 0 017.25 1.543V.75A.75.75 0 018 0zm-.75 3.056A5.004 5.004 0 003.056 7.25H5.25a.75.75 0 010 1.5H3.056a5.003 5.003 0 004.194 4.194V10.75a.75.75 0 111.5 0v2.194a5.002 5.002 0 004.194-4.194H10.75a.75.75 0 110-1.5h2.194A5.003 5.003 0 008.75 3.056V5.25a.75.75 0 01-1.5 0V3.056z"
          fill="currentColor"
        />
      </g>
      <defs>
        <clipPath id="clip0_1934_35984">
          <path fill="#fff" d="M0 0H16V16H0z" />
        </clipPath>
      </defs>
    </svg>
  )
}
