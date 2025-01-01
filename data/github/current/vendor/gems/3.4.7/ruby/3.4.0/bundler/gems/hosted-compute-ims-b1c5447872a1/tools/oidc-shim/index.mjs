import Provider from 'oidc-provider';
const configuration = {
  // refer to the documentation for other available configuration
  features: {
    clientCredentials: { enabled: true },
  },

  clients: [{
    client_id: "foo",
    client_secret: "bar",
    response_types: [ "code", "id_token" ],
    grant_types: [ "authorization_code", "implicit", "client_credentials", "password" ],
    redirect_uris: [ "https://token.docker.internal:8585/oidc/cb" ]
  }]
};

const oidc = new Provider('http://localhost:9000', configuration);
const oidcE2E = new Provider('http://oidc:9001', configuration);
const oidcE2EKube = new Provider('http://192.168.49.2:28139', configuration);

const parameters = ['username', 'password'];

async function passwordGrantType(ctx, next) {
  console.log("password grant type handler was called")
  if (ctx.oidc.params.username === 'foo' && ctx.oidc.params.password === 'bar') {

    const {
      AccessToken, IdToken,
    } = ctx.oidc.provider;
  
    const at = new AccessToken({
      accountId: 'foo',
      client: ctx.oidc.client,
      grantId: ctx.oidc.uuid,
    });

    const accessToken = await at.save();
    const expiresIn = AccessToken.expiresIn;

    // id_token
    const claims = {
      sub: 'foo',
    };

    const token = new IdToken(claims, {ctx});

    // set random nonce
    token.set('nonce', 'foobar');
    token.set('at_hash', accessToken);

    let idToken = await token.issue({ use: 'idtoken' });

    ctx.body = {
      access_token: accessToken,
      expires_in: expiresIn,
      id_token: idToken,
      token_type: 'Bearer',
    };
  } else {
    ctx.body = {
      error: 'invalid_grant',
      error_description: 'invalid credentials provided',
    };
    ctx.status = 400;
  }

  await next();
}

oidc.registerGrantType('password', passwordGrantType, parameters);
oidcE2E.registerGrantType('password', passwordGrantType, parameters);
oidcE2EKube.registerGrantType('password', passwordGrantType, parameters);

oidc.listen(9000, () => {
  console.log('oidc-provider listening on port 9000, check http://localhost:9000/.well-known/openid-configuration');
});

oidcE2E.listen(9001, () => {
  console.log('oidc-provider listening on port 9001, check http://oidc:9001/.well-known/openid-configuration');
});

oidcE2EKube.listen(9002, () => {
  console.log('oidc-provider listening on port 9002,  check http://192.168.49.2:28139/.well-known/openid-configuration');
});