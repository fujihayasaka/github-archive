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
  ListAlertsRequest,
  ListAlertsResponse,
  CountAlertsRequest,
  CountAlertsResponse,
} from "./public_monitoring_api";

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

export interface PublicMonitoringAPIClient {
  ListAlerts(request: ListAlertsRequest): Promise<ListAlertsResponse>;
  CountAlerts(request: CountAlertsRequest): Promise<CountAlertsResponse>;
}

export class PublicMonitoringAPIClientJSON
  implements PublicMonitoringAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ListAlerts.bind(this);
    this.CountAlerts.bind(this);
  }
  ListAlerts(request: ListAlertsRequest): Promise<ListAlertsResponse> {
    const data = ListAlertsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.publicmonitoring.v1.PublicMonitoringAPI",
      "ListAlerts",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListAlertsResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  CountAlerts(request: CountAlertsRequest): Promise<CountAlertsResponse> {
    const data = CountAlertsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.publicmonitoring.v1.PublicMonitoringAPI",
      "CountAlerts",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      CountAlertsResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }
}

export class PublicMonitoringAPIClientProtobuf
  implements PublicMonitoringAPIClient
{
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.ListAlerts.bind(this);
    this.CountAlerts.bind(this);
  }
  ListAlerts(request: ListAlertsRequest): Promise<ListAlertsResponse> {
    const data = ListAlertsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.publicmonitoring.v1.PublicMonitoringAPI",
      "ListAlerts",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListAlertsResponse.fromBinary(data as Uint8Array)
    );
  }

  CountAlerts(request: CountAlertsRequest): Promise<CountAlertsResponse> {
    const data = CountAlertsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.publicmonitoring.v1.PublicMonitoringAPI",
      "CountAlerts",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      CountAlertsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface PublicMonitoringAPITwirp<
  T extends TwirpContext = TwirpContext
> {
  ListAlerts(ctx: T, request: ListAlertsRequest): Promise<ListAlertsResponse>;
  CountAlerts(
    ctx: T,
    request: CountAlertsRequest
  ): Promise<CountAlertsResponse>;
}

export enum PublicMonitoringAPIMethod {
  ListAlerts = "ListAlerts",
  CountAlerts = "CountAlerts",
}

export const PublicMonitoringAPIMethodList = [
  PublicMonitoringAPIMethod.ListAlerts,
  PublicMonitoringAPIMethod.CountAlerts,
];

export function createPublicMonitoringAPIServer<
  T extends TwirpContext = TwirpContext
>(service: PublicMonitoringAPITwirp<T>) {
  return new TwirpServer<PublicMonitoringAPITwirp, T>({
    service,
    packageName: "github.secretscanning.publicmonitoring.v1",
    serviceName: "PublicMonitoringAPI",
    methodList: PublicMonitoringAPIMethodList,
    matchRoute: matchPublicMonitoringAPIRoute,
  });
}

function matchPublicMonitoringAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "ListAlerts":
      return async (
        ctx: T,
        service: PublicMonitoringAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, ListAlertsRequest, ListAlertsResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "ListAlerts" };
        await events.onMatch(ctx);
        return handlePublicMonitoringAPIListAlertsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "CountAlerts":
      return async (
        ctx: T,
        service: PublicMonitoringAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, CountAlertsRequest, CountAlertsResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "CountAlerts" };
        await events.onMatch(ctx);
        return handlePublicMonitoringAPICountAlertsRequest(
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

function handlePublicMonitoringAPIListAlertsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicMonitoringAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ListAlertsRequest, ListAlertsResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePublicMonitoringAPIListAlertsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePublicMonitoringAPIListAlertsProtobuf<T>(
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

function handlePublicMonitoringAPICountAlertsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicMonitoringAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, CountAlertsRequest, CountAlertsResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handlePublicMonitoringAPICountAlertsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handlePublicMonitoringAPICountAlertsProtobuf<T>(
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
async function handlePublicMonitoringAPIListAlertsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicMonitoringAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ListAlertsRequest, ListAlertsResponse>[]
) {
  let request: ListAlertsRequest;
  let response: ListAlertsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListAlertsRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListAlertsRequest,
      ListAlertsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListAlerts(ctx, inputReq);
    });
  } else {
    response = await service.ListAlerts(ctx, request!);
  }

  return JSON.stringify(
    ListAlertsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handlePublicMonitoringAPICountAlertsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicMonitoringAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, CountAlertsRequest, CountAlertsResponse>[]
) {
  let request: CountAlertsRequest;
  let response: CountAlertsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = CountAlertsRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CountAlertsRequest,
      CountAlertsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CountAlerts(ctx, inputReq);
    });
  } else {
    response = await service.CountAlerts(ctx, request!);
  }

  return JSON.stringify(
    CountAlertsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handlePublicMonitoringAPIListAlertsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicMonitoringAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, ListAlertsRequest, ListAlertsResponse>[]
) {
  let request: ListAlertsRequest;
  let response: ListAlertsResponse;

  try {
    request = ListAlertsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListAlertsRequest,
      ListAlertsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListAlerts(ctx, inputReq);
    });
  } else {
    response = await service.ListAlerts(ctx, request!);
  }

  return Buffer.from(ListAlertsResponse.toBinary(response));
}

async function handlePublicMonitoringAPICountAlertsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: PublicMonitoringAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, CountAlertsRequest, CountAlertsResponse>[]
) {
  let request: CountAlertsRequest;
  let response: CountAlertsResponse;

  try {
    request = CountAlertsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CountAlertsRequest,
      CountAlertsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CountAlerts(ctx, inputReq);
    });
  } else {
    response = await service.CountAlerts(ctx, request!);
  }

  return Buffer.from(CountAlertsResponse.toBinary(response));
}
