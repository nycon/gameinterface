<script setup lang="ts">
import { ref } from 'vue'
import {
  confirmTwoFactor,
  disableTwoFactor,
  enableTwoFactor,
} from '@/api/auth'
import { getErrorMessage } from '@/api/client'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const secret = ref('')
const otpauth = ref('')
const recovery = ref<string[]>([])
const code = ref('')
const password = ref('')
const error = ref<string | null>(null)
const info = ref<string | null>(null)

async function startEnable() {
  error.value = null
  try {
    const res = await enableTwoFactor()
    secret.value = res.secret
    otpauth.value = res.otpauth_url
    recovery.value = res.recovery_codes
  } catch (err) {
    error.value = getErrorMessage(err, '2FA konnte nicht gestartet werden')
  }
}

async function confirm() {
  error.value = null
  try {
    await confirmTwoFactor(code.value)
    info.value = '2FA aktiviert'
    secret.value = ''
    await auth.fetchUser()
  } catch (err) {
    error.value = getErrorMessage(err, 'Bestätigung fehlgeschlagen')
  }
}

async function disable() {
  error.value = null
  try {
    await disableTwoFactor(password.value)
    info.value = '2FA deaktiviert'
    password.value = ''
    await auth.fetchUser()
  } catch (err) {
    error.value = getErrorMessage(err, 'Deaktivieren fehlgeschlagen')
  }
}
</script>

<template>
  <div class="max-w-lg space-y-4">
    <h2 class="text-lg font-semibold">Sicherheit / 2FA</h2>
    <p class="text-sm text-panel-muted">
      Status:
      <span class="text-panel-accent">{{ auth.user?.two_factor_enabled ? 'aktiviert' : 'deaktiviert' }}</span>
    </p>
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <p v-if="info" class="text-sm text-panel-success">{{ info }}</p>

    <div v-if="!auth.user?.two_factor_enabled" class="space-y-3 border border-panel-border bg-panel-surface p-4">
      <button class="panel-btn-primary" @click="startEnable">2FA einrichten</button>
      <div v-if="secret" class="space-y-2 text-sm">
        <p>Secret: <code class="font-mono">{{ secret }}</code></p>
        <p class="break-all text-xs text-panel-muted">{{ otpauth }}</p>
        <p>Recovery Codes:</p>
        <ul class="font-mono text-xs">
          <li v-for="c in recovery" :key="c">{{ c }}</li>
        </ul>
        <input v-model="code" class="panel-input" placeholder="Code aus Authenticator" />
        <button class="panel-btn-primary" @click="confirm">Bestätigen</button>
      </div>
    </div>

    <div v-else class="space-y-2 border border-panel-border bg-panel-surface p-4">
      <input v-model="password" type="password" class="panel-input" placeholder="Passwort zur Deaktivierung" />
      <button class="panel-btn-secondary" @click="disable">2FA deaktivieren</button>
    </div>
  </div>
</template>
