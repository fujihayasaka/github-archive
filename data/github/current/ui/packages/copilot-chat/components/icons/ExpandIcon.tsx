export interface ExpandIconProps {
  className?: string
  size?: number
}

export function ExpandIcon({className, size}: ExpandIconProps) {
  return (
    <svg
      className={className}
      xmlns="http://www.w3.org/2000/svg"
      width={size || 14}
      height={size || 14}
      fill="none"
      viewBox="0 0 14 14"
      role="presentation"
    >
      <path
        fill="currentColor"
        fillRule="evenodd"
        d="M13.672 5.342a.8.8 0 0 0 .05-.295V.805a.75.75 0 0 0-.75-.75H8.73a.75.75 0 0 0 0 1.5h2.433L8.138 4.577A.75.75 0 0 0 9.2 5.638l3.024-3.023v2.432a.75.75 0 0 0 1.45.295M.328 8.657a.8.8 0 0 0-.05.295v4.243a.75.75 0 0 0 .75.75h4.243a.75.75 0 0 0 0-1.5H2.838l3.024-3.023A.75.75 0 1 0 4.8 8.362l-3.024 3.023V8.952a.75.75 0 0 0-1.45-.295"
        clipRule="evenodd"
      />
    </svg>
  )
}
