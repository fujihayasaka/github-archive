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
import { GetTenantRequest, GetTenantResponse } from "./tenant_api";

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

export interface TenantAPIClient {
  GetTenant(request: GetTenantRequest): Promise<GetTenantResponse>;
}

export class TenantAPIClientJSON implements TenantAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetTenant.bind(this);
  }
  GetTenant(request: GetTenantRequest): Promise<GetTenantResponse> {
    const data = GetTenantRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.tenant.v1.TenantAPI",
      "GetTenant",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTenantResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class TenantAPIClientProtobuf implements TenantAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetTenant.bind(this);
  }
  GetTenant(request: GetTenantRequest): Promise<GetTenantResponse> {
    const data = GetTenantRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.tenant.v1.TenantAPI",
      "GetTenant",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTenantResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface TenantAPITwirp<T extends TwirpContext = TwirpContext> {
  GetTenant(ctx: T, request: GetTenantRequest): Promise<GetTenantResponse>;
}

export enum TenantAPIMethod {
  GetTenant = "GetTenant",
}

export const TenantAPIMethodList = [TenantAPIMethod.GetTenant];

export function createTenantAPIServer<T extends TwirpContext = TwirpContext>(
  service: TenantAPITwirp<T>
) {
  return new TwirpServer<TenantAPITwirp, T>({
    service,
    packageName: "github.secretscanning.tenant.v1",
    serviceName: "TenantAPI",
    methodList: TenantAPIMethodList,
    matchRoute: matchTenantAPIRoute,
  });
}

function matchTenantAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetTenant":
      return async (
        ctx: T,
        service: TenantAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, GetTenantRequest, GetTenantResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "GetTenant" };
        await events.onMatch(ctx);
        return handleTenantAPIGetTenantRequest(
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

function handleTenantAPIGetTenantRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: TenantAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTenantRequest, GetTenantResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleTenantAPIGetTenantJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleTenantAPIGetTenantProtobuf<T>(
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
async function handleTenantAPIGetTenantJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TenantAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTenantRequest, GetTenantResponse>[]
) {
  let request: GetTenantRequest;
  let response: GetTenantResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTenantRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTenantRequest,
      GetTenantResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTenant(ctx, inputReq);
    });
  } else {
    response = await service.GetTenant(ctx, request!);
  }

  return JSON.stringify(
    GetTenantResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleTenantAPIGetTenantProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: TenantAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetTenantRequest, GetTenantResponse>[]
) {
  let request: GetTenantRequest;
  let response: GetTenantResponse;

  try {
    request = GetTenantRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTenantRequest,
      GetTenantResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTenant(ctx, inputReq);
    });
  } else {
    response = await service.GetTenant(ctx, request!);
  }

  return Buffer.from(GetTenantResponse.toBinary(response));
}
