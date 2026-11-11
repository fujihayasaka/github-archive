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
  GetOrganizationRequest,
  GetOrganizationResponse,
  ListOrganizationsRequest,
  ListOrganizationsResponse,
} from "./secret_scanning_organizations_api";

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

export interface OrganizationAPIClient {
  GetOrganization(
    request: GetOrganizationRequest
  ): Promise<GetOrganizationResponse>;
  ListOrganizations(
    request: ListOrganizationsRequest
  ): Promise<ListOrganizationsResponse>;
}

export class OrganizationAPIClientJSON implements OrganizationAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetOrganization.bind(this);
    this.ListOrganizations.bind(this);
  }
  GetOrganization(
    request: GetOrganizationRequest
  ): Promise<GetOrganizationResponse> {
    const data = GetOrganizationRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.organizations.v1.OrganizationAPI",
      "GetOrganization",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetOrganizationResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  ListOrganizations(
    request: ListOrganizationsRequest
  ): Promise<ListOrganizationsResponse> {
    const data = ListOrganizationsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.organizations.v1.OrganizationAPI",
      "ListOrganizations",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListOrganizationsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class OrganizationAPIClientProtobuf implements OrganizationAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetOrganization.bind(this);
    this.ListOrganizations.bind(this);
  }
  GetOrganization(
    request: GetOrganizationRequest
  ): Promise<GetOrganizationResponse> {
    const data = GetOrganizationRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.organizations.v1.OrganizationAPI",
      "GetOrganization",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetOrganizationResponse.fromBinary(data as Uint8Array)
    );
  }

  ListOrganizations(
    request: ListOrganizationsRequest
  ): Promise<ListOrganizationsResponse> {
    const data = ListOrganizationsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.organizations.v1.OrganizationAPI",
      "ListOrganizations",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListOrganizationsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface OrganizationAPITwirp<T extends TwirpContext = TwirpContext> {
  GetOrganization(
    ctx: T,
    request: GetOrganizationRequest
  ): Promise<GetOrganizationResponse>;
  ListOrganizations(
    ctx: T,
    request: ListOrganizationsRequest
  ): Promise<ListOrganizationsResponse>;
}

export enum OrganizationAPIMethod {
  GetOrganization = "GetOrganization",
  ListOrganizations = "ListOrganizations",
}

export const OrganizationAPIMethodList = [
  OrganizationAPIMethod.GetOrganization,
  OrganizationAPIMethod.ListOrganizations,
];

export function createOrganizationAPIServer<
  T extends TwirpContext = TwirpContext
>(service: OrganizationAPITwirp<T>) {
  return new TwirpServer<OrganizationAPITwirp, T>({
    service,
    packageName: "github.secretscanning.organizations.v1",
    serviceName: "OrganizationAPI",
    methodList: OrganizationAPIMethodList,
    matchRoute: matchOrganizationAPIRoute,
  });
}

function matchOrganizationAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetOrganization":
      return async (
        ctx: T,
        service: OrganizationAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetOrganizationRequest,
          GetOrganizationResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetOrganization" };
        await events.onMatch(ctx);
        return handleOrganizationAPIGetOrganizationRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ListOrganizations":
      return async (
        ctx: T,
        service: OrganizationAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ListOrganizationsRequest,
          ListOrganizationsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ListOrganizations" };
        await events.onMatch(ctx);
        return handleOrganizationAPIListOrganizationsRequest(
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

function handleOrganizationAPIGetOrganizationRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OrganizationAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetOrganizationRequest,
    GetOrganizationResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleOrganizationAPIGetOrganizationJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleOrganizationAPIGetOrganizationProtobuf<T>(
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

function handleOrganizationAPIListOrganizationsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OrganizationAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListOrganizationsRequest,
    ListOrganizationsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleOrganizationAPIListOrganizationsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleOrganizationAPIListOrganizationsProtobuf<T>(
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
async function handleOrganizationAPIGetOrganizationJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OrganizationAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetOrganizationRequest,
    GetOrganizationResponse
  >[]
) {
  let request: GetOrganizationRequest;
  let response: GetOrganizationResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetOrganizationRequest.fromJson(body, {
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
      GetOrganizationRequest,
      GetOrganizationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetOrganization(ctx, inputReq);
    });
  } else {
    response = await service.GetOrganization(ctx, request!);
  }

  return JSON.stringify(
    GetOrganizationResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleOrganizationAPIListOrganizationsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OrganizationAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListOrganizationsRequest,
    ListOrganizationsResponse
  >[]
) {
  let request: ListOrganizationsRequest;
  let response: ListOrganizationsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListOrganizationsRequest.fromJson(body, {
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
      ListOrganizationsRequest,
      ListOrganizationsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListOrganizations(ctx, inputReq);
    });
  } else {
    response = await service.ListOrganizations(ctx, request!);
  }

  return JSON.stringify(
    ListOrganizationsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleOrganizationAPIGetOrganizationProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OrganizationAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetOrganizationRequest,
    GetOrganizationResponse
  >[]
) {
  let request: GetOrganizationRequest;
  let response: GetOrganizationResponse;

  try {
    request = GetOrganizationRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetOrganizationRequest,
      GetOrganizationResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetOrganization(ctx, inputReq);
    });
  } else {
    response = await service.GetOrganization(ctx, request!);
  }

  return Buffer.from(GetOrganizationResponse.toBinary(response));
}

async function handleOrganizationAPIListOrganizationsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: OrganizationAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListOrganizationsRequest,
    ListOrganizationsResponse
  >[]
) {
  let request: ListOrganizationsRequest;
  let response: ListOrganizationsResponse;

  try {
    request = ListOrganizationsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListOrganizationsRequest,
      ListOrganizationsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListOrganizations(ctx, inputReq);
    });
  } else {
    response = await service.ListOrganizations(ctx, request!);
  }

  return Buffer.from(ListOrganizationsResponse.toBinary(response));
}
