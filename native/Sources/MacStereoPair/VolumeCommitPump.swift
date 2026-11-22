import Foundation

@MainActor
final class VolumeCommitPump {
    typealias Commit = @MainActor (Int) async -> Void
    typealias FinalCompletion = @MainActor () -> Void

    private let clock = ContinuousClock()
    private let initialPreviewDelay: Duration
    private let previewInterval: Duration
    private let defaultFinalDelay: Duration

    private var worker: Task<Void, Never>?
    private var commit: Commit?
    private var onFinalCommit: FinalCompletion?
    private var pendingPreview: Int?
    private var pendingFinal: (target: Int, delay: Duration)?
    private var lastPreviewSentAt: ContinuousClock.Instant?
    private var generation = 0

    init(
        initialPreviewDelay: Duration = .milliseconds(60),
        previewInterval: Duration = .milliseconds(120),
        defaultFinalDelay: Duration = .milliseconds(80)
    ) {
        self.initialPreviewDelay = initialPreviewDelay
        self.previewInterval = previewInterval
        self.defaultFinalDelay = defaultFinalDelay
    }

    func begin(
        commit: @escaping Commit,
        onFinalCommit: @escaping FinalCompletion
    ) {
        generation &+= 1
        self.commit = commit
        self.onFinalCommit = onFinalCommit
        pendingPreview = nil
        pendingFinal = nil
        lastPreviewSentAt = nil
    }

    func preview(_ target: Int) {
        guard commit != nil else { return }
        pendingFinal = nil
        pendingPreview = target
        startWorker()
    }

    func finish(_ target: Int, delay: Duration? = nil) {
        guard commit != nil else { return }
        pendingPreview = nil
        pendingFinal = (target, delay ?? defaultFinalDelay)
        startWorker()
    }

    func cancel() {
        generation &+= 1
        worker?.cancel()
        worker = nil
        commit = nil
        onFinalCommit = nil
        pendingPreview = nil
        pendingFinal = nil
        lastPreviewSentAt = nil
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !Task.isCancelled {
            if let final = pendingFinal {
                pendingFinal = nil
                let finalGeneration = generation
                do {
                    try await Task.sleep(for: final.delay)
                } catch {
                    break
                }
                guard generation == finalGeneration else { continue }
                if pendingFinal != nil {
                    continue
                }
                guard let commit else { break }
                await commit(final.target)
                guard !Task.isCancelled else { break }
                if pendingFinal != nil || generation != finalGeneration {
                    continue
                }
                pendingPreview = nil
                let completion = onFinalCommit
                onFinalCommit = nil
                worker = nil
                completion?()
                return
            }

            guard pendingPreview != nil else {
                worker = nil
                return
            }

            let wait: Duration
            if let lastPreviewSentAt {
                let elapsed = clock.now - lastPreviewSentAt
                wait = elapsed < previewInterval ? previewInterval - elapsed : .zero
            } else {
                wait = initialPreviewDelay
            }
            if wait > .zero {
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    break
                }
            }
            guard !Task.isCancelled else { break }
            if pendingFinal != nil {
                continue
            }
            guard let target = pendingPreview else { continue }
            pendingPreview = nil
            guard let commit else { break }
            await commit(target)
            lastPreviewSentAt = clock.now
        }

        worker = nil
        if !Task.isCancelled, pendingFinal != nil || pendingPreview != nil {
            startWorker()
        }
    }
}
