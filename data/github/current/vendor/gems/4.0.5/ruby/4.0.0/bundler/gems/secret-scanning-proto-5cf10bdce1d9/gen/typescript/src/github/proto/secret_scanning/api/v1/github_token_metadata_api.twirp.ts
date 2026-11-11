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
  GetGithubTokenMetadataRequest,
  GetGithubTokenMetadataResponse,
} from "./github_token_metadata_api";

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

export interface GithubTokenMetadataAPIClient {
  GetGithubTokenMetadata(
    request: GetGithubTokenMetadataRequest
  ): Promise<GetGithubTokenMetadataResponse>;
}

export class GithubTokenMetadataAPIClientJSON
  implements GithubTokenMetadataAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetGithubTokenMetadata.bind(this);
  }
  GetGithubTokenMetadata(
    request: GetGithubTokenMetadataRequest
  ): Promise<GetGithubTokenMetadataResponse> {
    const data = GetGithubTokenMetadataRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.GithubTokenMetadataAPI",
      "GetGithubTokenMetadata",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetGithubTokenMetadataResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class GithubTokenMetadataAPIClientProtobuf
  implements GithubTokenMetadataAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetGithubTokenMetadata.bind(this);
  }
  GetGithubTokenMetadata(
    request: GetGithubTokenMetadataRequest
  ): Promise<GetGithubTokenMetadataResponse> {
    const data = GetGithubTokenMetadataRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.GithubTokenMetadataAPI",
      "GetGithubTokenMetadata",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetGithubTokenMetadataResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface GithubTokenMetadataAPITwirp<
  T extends TwirpContext = TwirpContext
> {
  GetGithubTokenMetadata(
    ctx: T,
    request: GetGithubTokenMetadataRequest
  ): Promise<GetGithubTokenMetadataResponse>;
}

export enum GithubTokenMetadataAPIMethod {
  GetGithubTokenMetadata = "GetGithubTokenMetadata",
}

export const GithubTokenMetadataAPIMethodList = [
  GithubTokenMetadataAPIMethod.GetGithubTokenMetadata,
];

export function createGithubTokenMetadataAPIServer<
  T extends TwirpContext = TwirpContext
>(service: GithubTokenMetadataAPITwirp<T>) {
  return new TwirpServer<GithubTokenMetadataAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "GithubTokenMetadataAPI",
    methodList: GithubTokenMetadataAPIMethodList,
    matchRoute: matchGithubTokenMetadataAPIRoute,
  });
}

function matchGithubTokenMetadataAPIRoute<
  T extends TwirpContext = TwirpContext
>(method: string, events: RouterEvents<T>) {
  switch (method) {
    case "GetGithubTokenMetadata":
      return async (
        ctx: T,
        service: GithubTokenMetadataAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetGithubTokenMetadataRequest,
          GetGithubTokenMetadataResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetGithubTokenMetadata" };
        await events.onMatch(ctx);
        return handleGithubTokenMetadataAPIGetGithubTokenMetadataRequest(
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

function handleGithubTokenMetadataAPIGetGithubTokenMetadataRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: GithubTokenMetadataAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetGithubTokenMetadataRequest,
    GetGithubTokenMetadataResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleGithubTokenMetadataAPIGetGithubTokenMetadataJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleGithubTokenMetadataAPIGetGithubTokenMetadataProtobuf<T>(
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
async function handleGithubTokenMetadataAPIGetGithubTokenMetadataJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: GithubTokenMetadataAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetGithubTokenMetadataRequest,
    GetGithubTokenMetadataResponse
  >[]
) {
  let request: GetGithubTokenMetadataRequest;
  let response: GetGithubTokenMetadataResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetGithubTokenMetadataRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetGithubTokenMetadataRequest,
      GetGithubTokenMetadataResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetGithubTokenMetadata(ctx, inputReq);
    });
  } else {
    response = await service.GetGithubTokenMetadata(ctx, request!);
  }

  return JSON.stringify(
    GetGithubTokenMetadataResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleGithubTokenMetadataAPIGetGithubTokenMetadataProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: GithubTokenMetadataAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetGithubTokenMetadataRequest,
    GetGithubTokenMetadataResponse
  >[]
) {
  let request: GetGithubTokenMetadataRequest;
  let response: GetGithubTokenMetadataResponse;

  try {
    request = GetGithubTokenMetadataRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetGithubTokenMetadataRequest,
      GetGithubTokenMetadataResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetGithubTokenMetadata(ctx, inputReq);
    });
  } else {
    response = await service.GetGithubTokenMetadata(ctx, request!);
  }

  return Buffer.from(GetGithubTokenMetadataResponse.toBinary(response));
}
