package com.example.drugsearch

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * cleartext(http://)通信を禁止する設定が維持されていることを確認する(要件 非機能/セキュリティ、T03)。
 *
 * ユニットテストの作業ディレクトリは app モジュールのディレクトリになるため、ソースの XML を直接読む。
 */
class CleartextTrafficConfigTest {

    private val androidNs = "http://schemas.android.com/apk/res/android"

    private fun parse(path: String): Element {
        val file = File(path)
        assertTrue("$path が見つからない(作業ディレクトリ: ${File(".").absolutePath})", file.isFile)
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        return factory.newDocumentBuilder().parse(file).documentElement
    }

    private fun applicationElement(): Element {
        val manifest = parse("src/main/AndroidManifest.xml")
        val applications = manifest.getElementsByTagName("application")
        assertEquals(1, applications.length)
        return applications.item(0) as Element
    }

    @Test
    fun manifest_disablesCleartextTraffic() {
        assertEquals(
            "false",
            applicationElement().getAttributeNS(androidNs, "usesCleartextTraffic"),
        )
    }

    @Test
    fun manifest_referencesNetworkSecurityConfig() {
        assertEquals(
            "@xml/network_security_config",
            applicationElement().getAttributeNS(androidNs, "networkSecurityConfig"),
        )
    }

    @Test
    fun networkSecurityConfig_baseConfigForbidsCleartext() {
        val config = parse("src/main/res/xml/network_security_config.xml")
        val baseConfigs = config.getElementsByTagName("base-config")
        assertEquals(1, baseConfigs.length)
        assertEquals(
            "false",
            (baseConfigs.item(0) as Element).getAttribute("cleartextTrafficPermitted"),
        )
    }

    @Test
    fun networkSecurityConfig_hasNoCleartextException() {
        val config = parse("src/main/res/xml/network_security_config.xml")
        val domainConfigs = config.getElementsByTagName("domain-config")
        for (i in 0 until domainConfigs.length) {
            val permitted = (domainConfigs.item(i) as Element).getAttribute("cleartextTrafficPermitted")
            assertTrue("domain-config で cleartext を許可してはいけない", permitted != "true")
        }
    }

    @Test
    fun networkSecurityConfig_trustsOnlySystemCertificates() {
        val config = parse("src/main/res/xml/network_security_config.xml")
        assertEquals("debug-overrides で信頼設定を緩めてはいけない", 0, config.getElementsByTagName("debug-overrides").length)
        val certificates = config.getElementsByTagName("certificates")
        for (i in 0 until certificates.length) {
            assertEquals("system", (certificates.item(i) as Element).getAttribute("src"))
        }
    }

    @Test
    fun otherSourceSets_doNotOverrideSecurityConfig() {
        // debug / release などで manifest や network_security_config を差し替えると、main の検査をすり抜けるため禁止する
        val sourceSets = File("src").listFiles { f -> f.isDirectory && f.name !in setOf("main", "test", "androidTest") }.orEmpty()
        for (dir in sourceSets) {
            assertTrue("${dir.name} に AndroidManifest.xml を置いてはいけない", !File(dir, "AndroidManifest.xml").exists())
            assertTrue(
                "${dir.name} に network_security_config.xml を置いてはいけない",
                !File(dir, "res/xml/network_security_config.xml").exists(),
            )
        }
    }
}
