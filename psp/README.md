# Payment Service Providers (PSPs)

The `compose.yml` file in this directory declares 2 instances of the payment service, as well as their respective databases. The source code can be found [here](https://github.com/zanfranceschi/rinha-de-backend-2025-payment-processor).

> [!IMPORTANT]
> If you're going to run the simulation on an ARM64 CPU, make sure to use the appropriate tag `arm64-20250807221836` for the PSP image. Check the commented line in the `compose.yml` file.

Just run `docker compose up` here on this directory to get both PSPs available. They **need to be available before** the simulation starts.

## Endpoints

The 2 endpoints your service must integrate with are specified in the [instructions](../INSTRUCTIONS.md) for the challenge and thus aren't present here. The remaining ones are for **exclusive use** of K6 during the simulation and/or to help you with developing your solution.

Also according to the instructions, you can make requests from the host network to:

- `http://localhost:8001`
- `http://localhost:8002`

hitting the `default` and `fallback` PSPs, respectively.

### Public

As previously stated, the endpoints:

- `POST /payments`
- `GET /payments/service-health`

were specified already. The only public endpoint left is `GET /payments/<id>` for troubleshooting.

#### `GET /payments/<id>`

You can fetch information about a specific forwarded payment, giving its respective `id`. An example of a response body:

```json
{
   "correlationId": "4a7901b8-7d26-4d9d-aa19-4dc1c7cf60b3"
   "amount": 19.90,
   "requestedAt": "2025-07-15T12:34:56.000Z"
}
```

It's identical as the request body for the `POST /payments` endpoint your application must call to forward the payments.

The status code is `200 OK` if `id` is found. If `id` is not found, the status code is `404 NOT FOUND` or `400 BAD REQUEST` if `id` is not a valid UUID.

### Administrative

Accessing all following endpoints requires a custom header `X-Rinha-Token` in your request, holding what can be thought as a *root password* for the PSP. Hitting them without a token (or with the wrong one) would return a `401 UNAUTHORIZED` response.

The default token is `123` if you want access during development. However, at the beginning of the simulation, K6 will overwrite[^1] it so your application can't control the behavior of the PSPs.

#### `GET /admin/payments-summary?from=<timestamp>&to=<timestamp>`

This endpoint is the one **your** `GET /payments-summary` implemented endpoint will be compared against to check for consistency in the computed values. The query parameters `from` and `to` are the same as the ones implemented in your service.

It also shows information about the fees charged by that PSP. Below is an example of a response body:

```json
{
   "totalRequests": 43236,
   "totalAmount": 415542345.98,
   "totalFee": 415542.98,
   "feePerTransaction": 0.01
}
```

The fields `totalFee` and `feePerTransaction` are, respectively, the total amount of fee (USD) that PSP charged you for the payments and the rate for each payment it processes.

The status code is always `200 OK`.

#### `PUT /admin/configurations/token`

It sets the said *root password* for accessing all the `/admin` endpoints. The request body must be like the example below:

```json
{
   "token": "foo"
}
```

The field `token` must be a string. From now on, the `X-Rinha-Token` header must contain the string `"foo"` for the PSP accept your requests to the `/admin` endpoints.

The status code is always `204 NO CONTENT`.

#### `PUT /admin/configurations/delay`

It adds a delay in milliseconds for that PSP's response time. The request body must be like the example below:

```json
{
   "delay": 200
}
```

The field `delay` must be an integer. From now on, each response from that PSP will took **at least** 200ms.

The status code is always `204 NO CONTENT`.

#### `PUT /admin/configurations/failure`

It basically *enables/disables* that PSP. The request body must be like the example below:

```json
{
   "failure": true
}
```

The field `failure` must be a boolean. From now on, requests to that PSP will recieve `5XX` responses.

The status code is always `204 NO CONTENT`.

#### `POST /admin/purge-payments`

This endpoint simply truncates the `payments` table in that PSP's database. No request body is needed, and the response is:

```json
{
   "message": "All payments purged."
}
```

The status code is always `200 OK`.

[^1]: The test script for **this specific repository** doesn't actually do that since it wouldn't make sense given the purpose of this project. More information about that is found on the simulation's [`README.md` file](../simulation/README.md).
