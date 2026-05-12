class AuditLog {
  const AuditLog({
    required this.accion,
    this.mensaje,
    this.codigo,
    this.metadatos,
  });

  final String accion;
  final String? mensaje;
  final String? codigo;
  final Map<String, dynamic>? metadatos;

  Map<String, dynamic> toJson() {
    return {
      'accion': accion,
      'mensaje': mensaje,
      'codigo': codigo,
      'metadatos': metadatos,
    };
  }
}