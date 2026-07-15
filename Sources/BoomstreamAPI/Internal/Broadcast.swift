import Foundation

/// Мультикаст для `AsyncStream`: каждый вызов `stream()` даёт независимый стрим
/// (AsyncStream — single-consumer, а подписчиков может быть несколько).
/// `package`-доступ: используется player- и offline-таргетами, в публичный API не входит.
@MainActor
package final class Broadcast<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    package init() {}

    package func stream() -> AsyncStream<Element> {
        var captured: AsyncStream<Element>.Continuation!
        // Билд-замыкание AsyncStream выполняется синхронно до возврата init.
        let stream = AsyncStream<Element>(bufferingPolicy: .bufferingNewest(32)) { captured = $0 }
        let id = UUID()
        continuations[id] = captured
        captured.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuations[id] = nil
            }
        }
        return stream
    }

    package func yield(_ value: Element) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    package func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
