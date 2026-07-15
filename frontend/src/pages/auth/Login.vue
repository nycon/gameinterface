<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { isUserAdmin } from '@/types'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const email = ref('')
const password = ref('')
const code = ref('')
const localError = ref<string | null>(null)

async function submit() {
  localError.value = null
  try {
    if (auth.pendingChallenge) {
      const user = await auth.completeTwoFactor(code.value)
      const redirect =
        (route.query.redirect as string) ||
        (isUserAdmin(user) ? '/admin' : user.roles.includes('reseller') ? '/reseller' : '/client/servers')
      router.push(redirect)
      return
    }

    const result = await auth.login({ email: email.value, password: password.value })
    if (result.twoFactor) return

    const user = result.user!
    const redirect =
      (route.query.redirect as string) ||
      (isUserAdmin(user) ? '/admin' : user.roles.includes('reseller') ? '/reseller' : '/client/servers')
    router.push(redirect)
  } catch {
    localError.value = auth.error
  }
}
</script>

<template>
  <form class="border border-panel-border bg-panel-surface p-6" @submit.prevent="submit">
    <div class="space-y-4">
      <template v-if="!auth.pendingChallenge">
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">E-Mail</label>
          <input v-model="email" type="email" required class="panel-input" autocomplete="email" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Passwort</label>
          <input
            v-model="password"
            type="password"
            required
            class="panel-input"
            autocomplete="current-password"
          />
        </div>
      </template>
      <template v-else>
        <p class="text-sm text-panel-muted">Zwei-Faktor-Code aus der Authenticator-App eingeben.</p>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">2FA-Code</label>
          <input v-model="code" required class="panel-input font-mono" autocomplete="one-time-code" />
        </div>
      </template>
      <p v-if="localError || auth.error" class="text-xs text-panel-danger">
        {{ localError || auth.error }}
      </p>
      <button type="submit" class="panel-btn-primary w-full" :disabled="auth.loading">
        {{ auth.loading ? 'Anmelden…' : auth.pendingChallenge ? 'Bestätigen' : 'Anmelden' }}
      </button>
    </div>
  </form>
</template>
