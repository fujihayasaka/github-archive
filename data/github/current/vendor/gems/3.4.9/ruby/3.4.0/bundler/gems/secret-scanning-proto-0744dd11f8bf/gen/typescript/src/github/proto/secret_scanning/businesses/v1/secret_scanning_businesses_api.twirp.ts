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
  GetBusinessRequest,
  GetBusinessResponse,
} from "./secret_scanning_businesses_api";

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

export interface BusinessAPIClient {
  GetBusiness(request: GetBusinessRequest): Promise<GetBusinessResponse>;
}

export class BusinessAPIClientJSON implements BusinessAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetBusiness.bind(this);
  }
  GetBusiness(request: GetBusinessRequest): Promise<GetBusinessResponse> {
    const data = GetBusinessRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.businesses.v1.BusinessAPI",
      "GetBusiness",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetBusinessResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class BusinessAPIClientProtobuf implements BusinessAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetBusiness.bind(this);
  }
  GetBusiness(request: GetBusinessRequest): Promise<GetBusinessResponse> {
    const data = GetBusinessRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.businesses.v1.BusinessAPI",
      "GetBusiness",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetBusinessResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface BusinessAPITwirp<T extends TwirpContext = TwirpContext> {
  GetBusiness(
    ctx: T,
    request: GetBusinessRequest
  ): Promise<GetBusinessResponse>;
}

export enum BusinessAPIMethod {
  GetBusiness = "GetBusiness",
}

export const BusinessAPIMethodList = [BusinessAPIMethod.GetBusiness];

export function createBusinessAPIServer<T extends TwirpContext = TwirpContext>(
  service: BusinessAPITwirp<T>
) {
  return new TwirpServer<BusinessAPITwirp, T>({
    service,
    packageName: "github.secretscanning.businesses.v1",
    serviceName: "BusinessAPI",
    methodList: BusinessAPIMethodList,
    matchRoute: matchBusinessAPIRoute,
  });
}

function matchBusinessAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetBusiness":
      return async (
        ctx: T,
        service: BusinessAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, GetBusinessRequest, GetBusinessResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "GetBusiness" };
        await events.onMatch(ctx);
        return handleBusinessAPIGetBusinessRequest(
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

function handleBusinessAPIGetBusinessRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BusinessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetBusinessRequest, GetBusinessResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleBusinessAPIGetBusinessJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleBusinessAPIGetBusinessProtobuf<T>(
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
async function handleBusinessAPIGetBusinessJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BusinessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetBusinessRequest, GetBusinessResponse>[]
) {
  let request: GetBusinessRequest;
  let response: GetBusinessResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetBusinessRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBusinessRequest,
      GetBusinessResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBusiness(ctx, inputReq);
    });
  } else {
    response = await service.GetBusiness(ctx, request!);
  }

  return JSON.stringify(
    GetBusinessResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleBusinessAPIGetBusinessProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: BusinessAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetBusinessRequest, GetBusinessResponse>[]
) {
  let request: GetBusinessRequest;
  let response: GetBusinessResponse;

  try {
    request = GetBusinessRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetBusinessRequest,
      GetBusinessResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetBusiness(ctx, inputReq);
    });
  } else {
    response = await service.GetBusiness(ctx, request!);
  }

  return Buffer.from(GetBusinessResponse.toBinary(response));
}
