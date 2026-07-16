import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/app_styles.dart'; // Tetap dipertahankan jika Anda butuh referensi lain

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _nipController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _agreeTerms = false;

  // Tambahan state untuk menyembunyikan/menampilkan password
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Future<void> _register() async {
    if (!_agreeTerms) return _tampilkanError('Setujui syarat & ketentuan.');
    if (_passwordController.text != _confirmController.text) {
      return _tampilkanError('Password tidak cocok!');
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('http://192.168.100.234/backend-absensi/public/api/register'),
        headers: {
          'Accept':
              'application/json', // Tambahkan ini agar Laravel tahu ini API
        },
        body: {
          'name': _nameController.text,
          'nip': _nipController.text,
          'email': _emailController.text,
          'password': _passwordController.text,
        },
      );

      if (!mounted) return;
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Registrasi Berhasil!')));
        Navigator.pop(context);
      } else {
        _tampilkanError(
          jsonDecode(response.body)['message'] ?? 'Registrasi gagal.',
        );
      }
    } catch (e) {
      _tampilkanError("Terjadi kesalahan jaringan.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _tampilkanError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF), // Sesuai HTML
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56.0),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FF),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF14422D)),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "New Registration",
              style: TextStyle(
                color: Color(0xFF14422D),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: false,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- HEADER SECTION ---
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D5A43),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D5A43).withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_add_alt_1, // Ikon terdekat dengan desain
                  color: Color(0xFF9FCFB2),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Create Account",
                style: TextStyle(
                  color: Color(0xFF14422D),
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Join our secure workforce management\nsystem",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF717973),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // --- FORM SECTION ---
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D5A43).withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildInput(
                      label: "Full Name",
                      hint: "e.g. John Doe",
                      controller: _nameController,
                      icon: Icons.person_outline,
                    ),
                    _buildInput(
                      label: "Corporate ID",
                      hint: "e.g. EMP-2024-001",
                      controller: _nipController,
                      icon: Icons.badge_outlined,
                    ),
                    _buildInput(
                      label: "Email Address",
                      hint: "john.doe@company.com",
                      controller: _emailController,
                      icon: Icons.email_outlined,
                    ),
                    _buildInput(
                      label: "Password",
                      hint: "••••••••",
                      controller: _passwordController,
                      icon: Icons.lock_outline,
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    _buildInput(
                      label: "Confirm Password",
                      hint: "••••••••",
                      controller: _confirmController,
                      icon: Icons.lock_outline,
                      isPassword: true,
                      obscureText: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),

                    // TERMS & CONDITIONS CHECKBOX
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreeTerms,
                            onChanged: (v) => setState(() => _agreeTerms = v!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            side: const BorderSide(color: Color(0xFFC0C9C1)),
                            activeColor: const Color(0xFF14422D),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                  color: Color(0xFF717973),
                                  fontSize: 14,
                                  height: 1.25,
                                ),
                                children: [
                                  TextSpan(text: "I agree to the "),
                                  TextSpan(
                                    text: "Terms and Conditions",
                                    style: TextStyle(color: Color(0xFF14422D)),
                                  ),
                                  TextSpan(text: " and\n"),
                                  TextSpan(
                                    text: "Privacy Policy",
                                    style: TextStyle(color: Color(0xFF14422D)),
                                  ),
                                  TextSpan(text: "."),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- REGISTER BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14422D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Register Now",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // --- LOGIN LINK ---
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 16),
                    children: [
                      TextSpan(
                        text: "Already have an account? ",
                        style: TextStyle(color: Color(0xFF717973)),
                      ),
                      TextSpan(
                        text: "Login here",
                        style: TextStyle(
                          color: Color(0xFF7A5900),
                        ), // Warna gold/coklat dari HTML
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET INPUT GENERATOR ---
  Widget _buildInput({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Color(0xFF14422D),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF6B7280)),
              prefixIcon: Icon(icon, color: const Color(0xFF717973), size: 20),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscureText ? Icons.visibility_off : Icons.visibility,
                        color: const Color(0xFF717973),
                        size: 20,
                      ),
                      onPressed: onToggle,
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFC0C9C1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF14422D),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
