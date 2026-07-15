import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      redirect: () => {
        const auth = useAuthStore()
        if (!auth.isAuthenticated) return '/login'
        if (auth.isAdmin) return '/admin'
        if (auth.isReseller && auth.user?.roles.includes('reseller')) return '/reseller'
        return '/client/servers'
      },
    },
    {
      path: '/login',
      component: () => import('@/layouts/AuthLayout.vue'),
      meta: { guest: true },
      children: [
        {
          path: '',
          name: 'login',
          component: () => import('@/pages/auth/Login.vue'),
        },
      ],
    },
    {
      path: '/admin',
      component: () => import('@/layouts/AdminLayout.vue'),
      meta: { requiresAuth: true, requiresAdmin: true },
      children: [
        { path: '', name: 'admin-dashboard', component: () => import('@/pages/admin/Dashboard.vue') },
        { path: 'users', name: 'admin-users', component: () => import('@/pages/admin/Users.vue') },
        { path: 'nodes', name: 'admin-nodes', component: () => import('@/pages/admin/Nodes.vue') },
        { path: 'image-servers', name: 'admin-image-servers', component: () => import('@/pages/admin/ImageServers.vue') },
        { path: 'images', name: 'admin-images', component: () => import('@/pages/admin/Images.vue') },
        { path: 'templates', name: 'admin-templates', component: () => import('@/pages/admin/Templates.vue') },
        { path: 'servers', name: 'admin-servers', component: () => import('@/pages/admin/Servers.vue') },
        { path: 'allocations', name: 'admin-allocations', component: () => import('@/pages/admin/Allocations.vue') },
        { path: 'databases', name: 'admin-databases', component: () => import('@/pages/admin/Databases.vue') },
        { path: 'jobs', name: 'admin-jobs', component: () => import('@/pages/admin/Jobs.vue') },
        { path: 'audit-logs', name: 'admin-audit-logs', component: () => import('@/pages/admin/AuditLogs.vue') },
        { path: 'settings', name: 'admin-settings', component: () => import('@/pages/admin/Settings.vue') },
      ],
    },
    {
      path: '/reseller',
      component: () => import('@/layouts/ClientLayout.vue'),
      meta: { requiresAuth: true, requiresReseller: true },
      children: [
        { path: '', name: 'reseller-dashboard', component: () => import('@/pages/reseller/Dashboard.vue') },
      ],
    },
    {
      path: '/client',
      component: () => import('@/layouts/ClientLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        { path: 'servers', name: 'client-servers', component: () => import('@/pages/client/Servers.vue') },
        {
          path: 'servers/:id',
          component: () => import('@/pages/client/ServerDetail.vue'),
          children: [
            { path: '', redirect: (to) => ({ name: 'client-console', params: to.params }) },
            { path: 'console', name: 'client-console', component: () => import('@/pages/client/Console.vue') },
            { path: 'files', name: 'client-files', component: () => import('@/pages/client/Files.vue') },
            { path: 'backups', name: 'client-backups', component: () => import('@/pages/client/Backups.vue') },
            { path: 'databases', name: 'client-databases', component: () => import('@/pages/client/Databases.vue') },
            { path: 'ftp', name: 'client-ftp', component: () => import('@/pages/client/FtpAccounts.vue') },
          ],
        },
        { path: 'security', name: 'client-security', component: () => import('@/pages/client/Security.vue') },
      ],
    },
    {
      path: '/:pathMatch(.*)*',
      redirect: '/',
    },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (to.meta.guest && auth.isAuthenticated) {
    if (auth.isAdmin) return '/admin'
    if (auth.user?.roles.includes('reseller')) return '/reseller'
    return '/client/servers'
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  if (to.meta.requiresAdmin && !auth.isAdmin) {
    return '/client/servers'
  }

  if (to.meta.requiresReseller && !auth.isReseller) {
    return '/client/servers'
  }

  return true
})

export default router
