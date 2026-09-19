import tailwind from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Im Entwicklungsbetrieb zeigt /api auf die Vorführ-Auslieferung, damit es echte
// Daten gibt, ohne den Worker lokal laufen zu lassen.
export default defineConfig({
  plugins: [react(), tailwind()],
  server: {
    proxy: {
      '/api': {
        target: 'https://zapply-demo.bewerbungs-tracker.workers.dev',
        changeOrigin: true,
      },
    },
  },
})
