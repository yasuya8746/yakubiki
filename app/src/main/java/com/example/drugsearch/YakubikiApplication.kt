package com.example.drugsearch

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

/**
 * Hilt のエントリポイントとなる Application。
 *
 * WorkManager は Hilt で依存を注入した Worker(同期 Worker: T09)を使うため、
 * マニフェストで既定の自動初期化を外し、ここで HiltWorkerFactory を渡す。
 */
@HiltAndroidApp
class YakubikiApplication : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()
}
