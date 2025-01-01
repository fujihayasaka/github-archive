export function AttachmentPreviewImage(props: {src: string; alt?: string}) {
  return (
    <img
      src={props.src}
      alt={props.alt ?? 'attachment'}
      style={{
        width: '100%',
        height: '100%',
        objectFit: 'cover',
      }}
    />
  )
}
