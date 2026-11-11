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
  GetEnablementStatusForOrgRequest,
  GetEnablementStatusForOrgResponse,
} from "./enablement_status";

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

export interface EnablementStatusAPIClient {
  GetEnablementStatusForOrg(
    request: GetEnablementStatusForOrgRequest
  ): Promise<GetEnablementStatusForOrgResponse>;
}

export class EnablementStatusAPIClientJSON
  implements EnablementStatusAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetEnablementStatusForOrg.bind(this);
  }
  GetEnablementStatusForOrg(
    request: GetEnablementStatusForOrgRequest
  ): Promise<GetEnablementStatusForOrgResponse> {
    const data = GetEnablementStatusForOrgRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.EnablementStatusAPI",
      "GetEnablementStatusForOrg",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetEnablementStatusForOrgResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class EnablementStatusAPIClientProtobuf
  implements EnablementStatusAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetEnablementStatusForOrg.bind(this);
  }
  GetEnablementStatusForOrg(
    request: GetEnablementStatusForOrgRequest
  ): Promise<GetEnablementStatusForOrgResponse> {
    const data = GetEnablementStatusForOrgRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.EnablementStatusAPI",
      "GetEnablementStatusForOrg",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetEnablementStatusForOrgResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface EnablementStatusAPITwirp<
  T extends TwirpContext = TwirpContext
> {
  GetEnablementStatusForOrg(
    ctx: T,
    request: GetEnablementStatusForOrgRequest
  ): Promise<GetEnablementStatusForOrgResponse>;
}

export enum EnablementStatusAPIMethod {
  GetEnablementStatusForOrg = "GetEnablementStatusForOrg",
}

export const EnablementStatusAPIMethodList = [
  EnablementStatusAPIMethod.GetEnablementStatusForOrg,
];

export function createEnablementStatusAPIServer<
  T extends TwirpContext = TwirpContext
>(service: EnablementStatusAPITwirp<T>) {
  return new TwirpServer<EnablementStatusAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "EnablementStatusAPI",
    methodList: EnablementStatusAPIMethodList,
    matchRoute: matchEnablementStatusAPIRoute,
  });
}

function matchEnablementStatusAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetEnablementStatusForOrg":
      return async (
        ctx: T,
        service: EnablementStatusAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetEnablementStatusForOrgRequest,
          GetEnablementStatusForOrgResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetEnablementStatusForOrg" };
        await events.onMatch(ctx);
        return handleEnablementStatusAPIGetEnablementStatusForOrgRequest(
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

function handleEnablementStatusAPIGetEnablementStatusForOrgRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: EnablementStatusAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnablementStatusForOrgRequest,
    GetEnablementStatusForOrgResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleEnablementStatusAPIGetEnablementStatusForOrgJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleEnablementStatusAPIGetEnablementStatusForOrgProtobuf<T>(
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
async function handleEnablementStatusAPIGetEnablementStatusForOrgJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: EnablementStatusAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnablementStatusForOrgRequest,
    GetEnablementStatusForOrgResponse
  >[]
) {
  let request: GetEnablementStatusForOrgRequest;
  let response: GetEnablementStatusForOrgResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetEnablementStatusForOrgRequest.fromJson(body, {
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
      GetEnablementStatusForOrgRequest,
      GetEnablementStatusForOrgResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetEnablementStatusForOrg(ctx, inputReq);
    });
  } else {
    response = await service.GetEnablementStatusForOrg(ctx, request!);
  }

  return JSON.stringify(
    GetEnablementStatusForOrgResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleEnablementStatusAPIGetEnablementStatusForOrgProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: EnablementStatusAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnablementStatusForOrgRequest,
    GetEnablementStatusForOrgResponse
  >[]
) {
  let request: GetEnablementStatusForOrgRequest;
  let response: GetEnablementStatusForOrgResponse;

  try {
    request = GetEnablementStatusForOrgRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetEnablementStatusForOrgRequest,
      GetEnablementStatusForOrgResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetEnablementStatusForOrg(ctx, inputReq);
    });
  } else {
    response = await service.GetEnablementStatusForOrg(ctx, request!);
  }

  return Buffer.from(GetEnablementStatusForOrgResponse.toBinary(response));
}
