import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { ThemeProvider, useTheme } from '../theme';

/**
 * Layout raiz. Os tokens começam no template padrão (teal-clean) e serão sobrepostos
 * pela marca do tenant após o login: ler org_branding no banco e chamar
 * useTheme().setTenantBranding(palette).
 */
export default function RootLayout() {
  return (
    <SafeAreaProvider>
      {/* TODO(auth): <AuthProvider> ao redor — ao logar, buscar o branding do tenant. */}
      <ThemeProvider>
        <RootNavigator />
      </ThemeProvider>
    </SafeAreaProvider>
  );
}

function RootNavigator() {
  const { tokens } = useTheme();
  return (
    <>
      <StatusBar style="dark" />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: tokens.bg },
        }}
      />
    </>
  );
}
