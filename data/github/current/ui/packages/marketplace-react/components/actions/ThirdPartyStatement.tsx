interface ThirdPartyStatementProps {
  isThirdParty: boolean
  name?: string
}

export function ThirdPartyStatement(props: ThirdPartyStatementProps) {
  const {isThirdParty, name} = props

  return (
    <>
      {isThirdParty && name && (
        <p className="note m-0" data-testid={'third-party-statement'}>
          <strong>{name}</strong> is not certified by GitHub. It is provided by a third-party and is governed by
          separate terms of service, privacy policy, and support documentation.
        </p>
      )}
    </>
  )
}
