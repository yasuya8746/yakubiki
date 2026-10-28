package com.example.drugsearch.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/**
 * アプリ全体で共有する依存の提供場所。
 *
 * T03 時点では空。Room の Database / DAO は T08、Retrofit / OkHttp は T09 で追加する
 * (配信先 URL とデータ形式が T05・T07 で決まってから)。
 */
@Module
@InstallIn(SingletonComponent::class)
object AppModule
