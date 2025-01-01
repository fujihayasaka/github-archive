import {Grid, Footnotes} from '@primer/react-brand'
import {analyticsEvent} from '../../../../lib/analytics'

export default function FootnotesSection() {
  return (
    <section id="footnotes" className="lp-Section lp-Section--level-1 lp-Section--footnotes" style={{paddingTop: '0'}}>
      <Grid className="lp-Grid--noRowGap">
        <Grid.Column span={12}>
          <Footnotes>
            <Footnotes.Item id="footnote-1" href="#footnote-ref-1-1">
              <a
                className="lp-Link--inline"
                href="https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-saml-single-sign-on/about-authentication-with-saml-single-sign-on"
                {...analyticsEvent({
                  action: 'saml_sso',
                  tag: 'link',
                  context: 'footnote',
                  location: 'features_table',
                })}
              >
                Authentication with SAML single sign-on (SSO)
              </a>{' '}
              available for organizations using GitHub Enterprise Cloud.
            </Footnotes.Item>
          </Footnotes>
        </Grid.Column>
      </Grid>
    </section>
  )
}
