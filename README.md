# FynnEdge

**FynnEdge Advisory — Simplifying Loan, Amplifying Trust.**

A standalone Flutter application. It shares no code, database, API, auth or
models with `fynn_on` or any other existing system.

---

## Running it

```bash
flutter run                      # mock data, no backend needed
flutter run -d linux             # desktop window is phone-sized for review
```

The app boots straight into the customer journey with realistic development
data. No backend, OTP provider, AI key or lender integration is required.

---

## Swapping mock services for your real API

This is a one-line change, and no UI or controller code moves.

Every service has two implementations behind one interface — for example
`HomeService` is implemented by both `MockHomeService` and `ApiHomeService`.
The choice is made in exactly one place, [`lib/app/providers.dart`](lib/app/providers.dart),
driven by a compile-time flag:

```dart
final homeServiceProvider = Provider<HomeService>(
  (ref) => ApiConfig.useMock
      ? const MockHomeService()
      : ApiHomeService(ref.watch(apiClientProvider)),
);
```

To point the app at a real backend:

```bash
flutter run \
  --dart-define=FYNN_USE_MOCK=false \
  --dart-define=FYNN_API_BASE=https://api.fynnedge.com
```

Screens, controllers and repositories are untouched by this — they only ever
see the interface.

### The data flow

```
Screen  →  Riverpod provider  →  Repository  →  Service  →  API or mock
```

- **Screens** render. They never call a service or build a URL.
- **Repositories** compose and cache. `LoanRepository` is the interesting one:
  it prices raw products into offers using the local finance engine, so EMI
  figures are identical whether the catalogue came from mock data or the wire.
- **Services** are pure transport. One interface, two implementations.

### Where the fake data lives

All of it is in [`lib/data/mock/mock_data.dart`](lib/data/mock/mock_data.dart)
and nowhere else. Lender names are fictional on purpose so screenshots can
never be mistaken for live market pricing.

---

## Financial calculations are never mocked

[`FinanceService`](lib/data/services/finance_service.dart) is real arithmetic
that runs on-device and always will. EMI, amortisation, affordability,
prepayment, balance transfer and emergency-fund maths do not depend on the
network, and a backend swap cannot change what a number means.

It is covered directly by [`test/widget_test.dart`](test/widget_test.dart) —
the standard reducing-balance formula, verified against known values.

---

## Tests

```bash
flutter test                     # everything; the API suite skips if no backend
flutter test --update-goldens    # refresh the screenshots in test/goldens
```

| Suite | What it guards |
|---|---|
| `finance_test.dart` | The EMI engine, cross-checked against a month-by-month simulation that must close the balance to zero. Independent of the closed-form formula. |
| `model_parsing_test.dart` | Every model against the awkward JSON a real backend emits — nulls, absent keys, `[]` where an object was expected, numbers as strings, unparseable dates. |
| `screens_test.dart` | Renders all 29 screens and writes a PNG per screen. A screen that overflows, throws or reads a missing provider fails here. |
| `responsive_test.dart` | Every screen at 360x640, 390x844 and 430x932, plus small-phone goldens for the dense screens. |
| `keyboard_test.dart` | Input screens with a raised keyboard, including that the CTA can still be reached. |
| `navigation_flow_test.dart` | Drives the real router through the full 25-screen journey, signup included. |
| `routes_test.dart` | Every constant in `Routes` resolves to a real screen, so a renamed path cannot leave a dead link. |
| `api_contract_test.dart` | Parses live Laravel responses through the real models, error paths included. |

The API suite needs the backend:

```bash
cd ../fynnedge-api && php artisan serve --port=8123
flutter test --dart-define=FYNN_API_BASE=http://127.0.0.1:8123
```

### Determinism

Anything the customer sees that depends on the current time reads
`AppClock.now()`, never `DateTime.now()`. Tests freeze it, so greetings,
relative timestamps and seeded dates do not drift and goldens stay stable.

## Structure

```
lib/
  app/            theme, router, routes, Riverpod wiring (providers.dart = the swap point)
  core/           clock, formatters and the shared widget kit
  data/
    models/       plain classes with fromJson/toJson
    services/     transport: one interface, a Mock and an Api implementation
    repositories/ what controllers talk to
    mock/         every fake value in the app, in one file
  features/       one folder per area, screens + their controllers
```

State management is **Riverpod only** — no Bloc, Provider or GetX mixed in.

---

## What is deliberately not real yet

Placeholders with clean integration points, waiting on your providers:

| Area | Today | Swap in |
|---|---|---|
| OTP | any 6 digits except `000000` | your SMS provider, in `AuthService` |
| Lender offers | 6 fictional products | real catalogue, in `CatalogService` |
| FynnAI | rule-based, reads real financials | a model provider, in `AiService` |
| Document OCR | staged mock extraction | real pipeline, in `DocumentService` |
| Storage | local | private cloud, in `DocumentService` |
| Credit data | not called | bureau integration |

Applications are read-only — submission is stubbed until lender integrations
exist. Two FynnLab tools (Debt Calculator, Future Simulator) are listed but
marked "soon" rather than faked.
