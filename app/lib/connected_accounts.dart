import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'opportunity_assessment.dart';
import 'thaid.dart';

typedef DemoConnection = ({
  String field,
  String source,
  String value,
  String? checkedAt,
});

class ProfileDemo {
  const ProfileDemo._(this.profile, this.identity, this.connections);

  final Map<String, dynamic> profile;
  final ThaidProfileIdentity? identity;
  final List<DemoConnection> connections;

  static ProfileDemo? fromResponse(Map<String, dynamic> response) {
    if (response case {'dataStatus': 'mock', 'sources': final List sources}) {
      final identity = response['identity'];
      return ProfileDemo._(
        response['profile'] is Map<String, dynamic> ? response['profile'] : {},
        identity is Map<String, dynamic> && identity['dataStatus'] == 'mock'
            ? ThaidProfileIdentity(identity)
            : null,
        [
          for (final source in sources)
            if (source case {
              'field': final String field,
              'label': final String label,
              'value': final String value,
            })
              (
                field: field,
                source: label,
                value: value,
                checkedAt: source['checkedAt'] is String
                    ? source['checkedAt'] as String
                    : null,
              ),
        ],
      );
    }
    return null;
  }
}

enum AccountStatus { loading, disconnected, skipped, failed, connected }

class ConnectedAccount {
  const ConnectedAccount(
    this.status, {
    this.identity,
    this.detail,
    this.checkedAt,
    this.mock = false,
  });

  final AccountStatus status;
  final ThaidProfileIdentity? identity;
  final String? detail, checkedAt;
  final bool mock;
}

class AccountsSnapshot {
  const AccountsSnapshot({
    this.accounts = const {},
    this.config = const {},
    this.initializing = true,
    this.govAvailable = false,
    this.govLinked = false,
  });

  final Map<DemoSource, ConnectedAccount> accounts;
  final Map<String, dynamic> config;
  final bool initializing, govAvailable, govLinked;

  bool get userMode => config['mode'] == 'user';
  bool get demoEnabled => DemoSource.enabled(config);
  int get connectedCount => accounts.values
      .where((account) => account.status == AccountStatus.connected)
      .length;
  bool get hasMock => accounts.values.any((account) => account.mock);

  ConnectedAccount operator [](DemoSource source) =>
      accounts[source] ??
      ConnectedAccount(
        initializing ? AccountStatus.loading : AccountStatus.disconnected,
      );

  ConnectedAccount get thaid => this[DemoSource.thaid];
}

/// The profile and Me tab observe the same provider results. Requests only
/// publish while their server, choices and refresh generation are current.
class ConnectedAccounts extends ValueNotifier<AccountsSnapshot> {
  ConnectedAccounts(this.api) : super(const AccountsSnapshot());

  final Api api;
  int _generation = 0;
  ({String server, String choices})? _scope;
  bool _deleting = false;

  Future<void> refresh({bool force = false, DemoSource? retry}) async {
    final scope = (server: api.baseUrl, choices: api.onboardingChoices);
    if (_deleting || (!force && retry == null && _scope == scope)) return;
    final previous = _scope == scope ? value : const AccountsSnapshot();
    _scope = scope;
    final generation = ++_generation;
    bool current() =>
        generation == _generation &&
        api.baseUrl == scope.server &&
        api.onboardingChoices == scope.choices;
    final rows = <DemoSource, ConnectedAccount>{};
    Map<String, dynamic> config = {};
    var govAvailable = false;
    var govLinked = false;
    void publish({bool initializing = false}) {
      if (!current()) return;
      value = AccountsSnapshot(
        accounts: Map.unmodifiable(rows),
        config: config,
        initializing: initializing,
        govAvailable: govAvailable,
        govLinked: govLinked,
      );
    }

    if (retry == null) publish(initializing: true);
    try {
      config = await api
          .get('/v1/app-config')
          .timeout(const Duration(seconds: 5));
    } on ApiException {
      // Only a confirmed DEMO configuration can load samples.
    } on TimeoutException {
      // The real link can still be checked when configuration is unavailable.
    }
    if (!current()) return;
    final demo = DemoSource.enabled(config);
    final singleRetry =
        retry != null &&
        previous.config.isNotEmpty &&
        previous.config['mode'] == config['mode'] &&
        previous.demoEnabled == demo;
    final selected = <DemoSource>[];
    for (final source in DemoSource.values) {
      final answer = demo ? source.answer(scope.choices) : '';
      final keep =
          singleRetry &&
          source != retry &&
          previous[source].status != AccountStatus.loading;
      rows[source] = keep
          ? previous[source]
          : switch (answer) {
              'y' => const ConnectedAccount(AccountStatus.loading),
              'n' => const ConnectedAccount(AccountStatus.skipped),
              _ => const ConnectedAccount(AccountStatus.disconnected),
            };
      if (answer == 'y' && !keep) selected.add(source);
    }

    if (singleRetry &&
        retry != DemoSource.thaid &&
        previous.thaid.status != AccountStatus.loading) {
      govAvailable = previous.govAvailable;
      govLinked = previous.govLinked;
    } else {
      final disconnected = rows[DemoSource.thaid]!;
      rows[DemoSource.thaid] = const ConnectedAccount(AccountStatus.loading);
      publish();
      final link = await _readThaid(demo, disconnected);
      if (!current()) return;
      govAvailable = link.available;
      govLinked = link.account.status == AccountStatus.connected;
      if (govLinked) {
        selected.remove(DemoSource.thaid);
      }
      rows[DemoSource.thaid] = selected.contains(DemoSource.thaid)
          ? const ConnectedAccount(AccountStatus.loading)
          : link.account;
    }
    publish();
    if (selected.isEmpty) return;

    ProfileDemo? result;
    try {
      result = ProfileDemo.fromResponse(
        await api
            .get(DemoSource.personaPath(selected))
            .timeout(const Duration(seconds: 8)),
      );
    } on ApiException {
      // Missing responses are retryable per service.
    } on TimeoutException {
      // A timeout must not remove other successful results.
    }
    if (!current()) return;
    final details = {
      for (final row in result?.connections ?? <DemoConnection>[])
        row.field: row,
    };
    for (final source in selected) {
      final detail = details[source.field];
      rows[source] = detail == null
          ? const ConnectedAccount(AccountStatus.failed)
          : ConnectedAccount(
              AccountStatus.connected,
              identity: source == DemoSource.thaid
                  ? result!.identity ??
                        ThaidProfileIdentity({'dataStatus': 'mock'})
                  : null,
              detail: detail.value,
              checkedAt: detail.checkedAt,
              mock: true,
            );
    }
    publish();
  }

  Future<({ConnectedAccount account, bool available})> _readThaid(
    bool demo,
    ConnectedAccount disconnected,
  ) async {
    try {
      final link = await api
          .get('/v1/me/gov-link')
          .timeout(const Duration(seconds: 5));
      final identity = link['identity'];
      final live =
          link['mock'] != true &&
          identity is Map &&
          identity['dataStatus'] == 'live' &&
          identity['claimsVerified'] == true;
      if (link['status'] != 'connected' || (!demo && !live)) {
        return (account: disconnected, available: demo);
      }
      return (
        account: ConnectedAccount(
          AccountStatus.connected,
          identity: ThaidProfileIdentity(
            identity is Map<String, dynamic>
                ? identity
                : {'dataStatus': 'mock'},
          ),
          checkedAt: profileText(link['connectedAt']),
          mock: !live,
        ),
        available: demo,
      );
    } on ApiException catch (error) {
      return (
        account: error.status == 403 || error.status == 404
            ? disconnected
            : const ConnectedAccount(AccountStatus.failed),
        available: false,
      );
    } on TimeoutException {
      return (
        account: const ConnectedAccount(AccountStatus.failed),
        available: false,
      );
    }
  }

  void beginDelete() {
    _deleting = true;
    _generation++;
    _scope = null;
    value = const AccountsSnapshot();
  }

  void endDelete() {
    _deleting = false;
  }

  void forgetDemoThaid() {
    final choices = api.onboardingChoices;
    if (DemoSource.thaid.answer(choices) == 'y') {
      api.saveOnboardingChoices('d${choices.substring(1)}');
    }
  }
}

String? profileText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String? checkedDate(String? value) {
  if (value == null) return null;
  final date = DateTime.tryParse(value);
  if (date == null) return null;
  final day = value.contains('T')
      ? date.toUtc().add(const Duration(hours: 7))
      : date;
  return '${day.day}/${day.month}/${day.year + 543}';
}
