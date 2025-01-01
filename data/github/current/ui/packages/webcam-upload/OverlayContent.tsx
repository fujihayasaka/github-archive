export function OverlayContent({content}: {content: string | number | null}) {
  if (content === null) return null

  const defaultStyles: React.CSSProperties = {
    position: 'absolute',
    top: 0,
    left: 0,
    width: '100%',
    height: '100%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    color: 'white',
    fontSize: '48px',
    fontWeight: 'bold',
    zIndex: 1,
  }

  return <div style={defaultStyles}>{content}</div>
}
