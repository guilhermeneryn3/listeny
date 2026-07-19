import { GraduationCap } from 'lucide-react-native';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { spacing, typography, useTheme } from '../theme';

/**
 * Tela placeholder da Fase 0 — prova que o app boota e consome os tokens do tema.
 * Sem dados falsos; a marca virá do tenant após o login.
 */
export default function Index() {
  const { tokens } = useTheme();

  return (
    <SafeAreaView style={[styles.safe, { backgroundColor: tokens.bg }]}>
      <View style={styles.center}>
        <View
          style={[
            styles.badge,
            {
              backgroundColor: tokens.tint,
              borderColor: tokens.edge,
              borderRadius: tokens.radius,
            },
          ]}
        >
          <GraduationCap color={tokens.primary} size={40} strokeWidth={2.2} />
        </View>

        <Text
          style={[
            typography.display,
            { color: tokens.ink, fontFamily: tokens.font, marginTop: spacing.xl },
          ]}
        >
          Listeny
        </Text>
        <Text
          style={[
            typography.body,
            { color: tokens.sub, fontFamily: tokens.font, marginTop: spacing.sm },
          ]}
        >
          Base pronta
        </Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1 },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.xxl,
  },
  badge: {
    width: 88,
    height: 88,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
});
