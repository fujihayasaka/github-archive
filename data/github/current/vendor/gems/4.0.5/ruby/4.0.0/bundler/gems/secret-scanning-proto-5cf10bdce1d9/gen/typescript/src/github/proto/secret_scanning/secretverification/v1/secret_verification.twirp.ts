import {
  TwirpContext,
  TwirpServer,
  RouterEvents,
  TwirpError,
  TwirpErrorCode,
  Interceptor,
  TwirpContentType,
  chainInterceptors,
} from "twirp-ts";
import {
  VerifySecretRequest,
  VerifySecretResponse,
} from "./secret_verification";

//==================================//
//          Client Code             //
//==================================//

interface Rpc {
  request(
    service: string,
    method: string,
    contentType: "application/json" | "application/protobuf",
    data: object | Uint8Array
  ): Promise<object | Uint8Array>;
}

export interface SecretVerificationServiceClient {
  VerifySecret(request: VerifySecretRequest): Promise<VerifySecretResponse>;
}

export class SecretVerificationServiceClientJSON
  implements SecretVerificationServiceClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.VerifySecret.bind(this);
  }
  VerifySecret(request: VerifySecretRequest): Promise<VerifySecretResponse> {
    const data = VerifySecretRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.secretverification.v1.SecretVerificationService",
      "VerifySecret",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      VerifySecretResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class SecretVerificationServiceClientProtobuf
  implements SecretVerificationServiceClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.VerifySecret.bind(this);
  }
  VerifySecret(request: VerifySecretRequest): Promise<VerifySecretResponse> {
    const data = VerifySecretRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.secretverification.v1.SecretVerificationService",
      "VerifySecret",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      VerifySecretResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface SecretVerificationServiceTwirp<
  T extends TwirpContext = TwirpContext
> {
  VerifySecret(
    ctx: T,
    request: VerifySecretRequest
  ): Promise<VerifySecretResponse>;
}

export enum SecretVerificationServiceMethod {
  VerifySecret = "VerifySecret",
}

export const SecretVerificationServiceMethodList = [
  SecretVerificationServiceMethod.VerifySecret,
];

export function createSecretVerificationServiceServer<
  T extends TwirpContext = TwirpContext
>(service: SecretVerificationServiceTwirp<T>) {
  return new TwirpServer<SecretVerificationServiceTwirp, T>({
    service,
    packageName: "github.secretscanning.secretverification.v1",
    serviceName: "SecretVerificationService",
    methodList: SecretVerificationServiceMethodList,
    matchRoute: matchSecretVerificationServiceRoute,
  });
}

function matchSecretVerificationServiceRoute<
  T extends TwirpContext = TwirpContext
>(method: string, events: RouterEvents<T>) {
  switch (method) {
    case "VerifySecret":
      return async (
        ctx: T,
        service: SecretVerificationServiceTwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          VerifySecretRequest,
          VerifySecretResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "VerifySecret" };
        await events.onMatch(ctx);
        return handleSecretVerificationServiceVerifySecretRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    default:
      events.onNotFound();
      const msg = `no handler found`;
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleSecretVerificationServiceVerifySecretRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: SecretVerificationServiceTwirp,
  data: Buffer,
  interceptors?: Interceptor<T, VerifySecretRequest, VerifySecretResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleSecretVerificationServiceVerifySecretJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleSecretVerificationServiceVerifySecretProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}
async function handleSecretVerificationServiceVerifySecretJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: SecretVerificationServiceTwirp,
  data: Buffer,
  interceptors?: Interceptor<T, VerifySecretRequest, VerifySecretResponse>[]
) {
  let request: VerifySecretRequest;
  let response: VerifySecretResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = VerifySecretRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      VerifySecretRequest,
      VerifySecretResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifySecret(ctx, inputReq);
    });
  } else {
    response = await service.VerifySecret(ctx, request!);
  }

  return JSON.stringify(
    VerifySecretResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleSecretVerificationServiceVerifySecretProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: SecretVerificationServiceTwirp,
  data: Buffer,
  interceptors?: Interceptor<T, VerifySecretRequest, VerifySecretResponse>[]
) {
  let request: VerifySecretRequest;
  let response: VerifySecretResponse;

  try {
    request = VerifySecretRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      VerifySecretRequest,
      VerifySecretResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.VerifySecret(ctx, inputReq);
    });
  } else {
    response = await service.VerifySecret(ctx, request!);
  }

  return Buffer.from(VerifySecretResponse.toBinary(response));
}
