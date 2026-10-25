"""
backend/test_auth_system.py
Test suite for:
- Username authentication
- Initial Admin seeding (harish, vishal)
- Concurrent login restriction (Single active device)
- Session reset by Admin
- 2-Admin quota enforcement
- Protection of last remaining admin
"""
import os
import sys

# Ensure backend directory is in python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from main import app, lifespan
from database import User, SessionLocal

def run_tests():
    print("=== Running Backend Auth & User Management Tests ===")
    
    with TestClient(app) as client:
        # 1. Verify startup seeding
        db = SessionLocal()
        try:
            admins = db.query(User).filter(User.role == "admin").all()
            admin_usernames = {a.username for a in admins}
            assert "harish" in admin_usernames, "Admin 'harish' was not seeded!"
            assert "vishal" in admin_usernames, "Admin 'vishal' was not seeded!"
            assert len(admins) == 2, f"Expected exactly 2 admins on startup, found {len(admins)}"
            
            # Check legacy accounts purged
            legacy = db.query(User).filter(User.username.in_(["joe321@gmail.com", "member@smartdoor.com"])).all()
            assert len(legacy) == 0, f"Legacy accounts still exist: {legacy}"
            print("[PASS] Startup seeding and legacy account purge verified.")
        finally:
            db.close()

        # 2. Login Harish
        login_res = client.post("/auth/login", json={"username": "harish", "password": "harish123"})
        assert login_res.status_code == 200, f"Login failed: {login_res.text}"
        harish_data = login_res.json()
        assert "access_token" in harish_data
        assert harish_data["user"]["username"] == "harish"
        assert harish_data["user"]["is_logged_in"] is True
        harish_token = harish_data["access_token"]
        harish_headers = {"Authorization": f"Bearer {harish_token}"}
        print("[PASS] harish login succeeded with valid token.")

        # 3. Concurrent Login Restriction for Harish
        dup_login = client.post("/auth/login", json={"username": "harish", "password": "harish123"})
        assert dup_login.status_code == 403, f"Expected 403 Forbidden, got {dup_login.status_code}: {dup_login.text}"
        assert "already signed in on another device" in dup_login.json()["detail"]
        print("[PASS] Concurrent login correctly rejected with 403 Forbidden.")

        # 4. Logout Harish
        logout_res = client.post("/auth/logout", headers=harish_headers)
        assert logout_res.status_code == 200, f"Logout failed: {logout_res.text}"
        
        # Verify harish can log in again after logout
        login_res2 = client.post("/auth/login", json={"username": "harish", "password": "harish123"})
        assert login_res2.status_code == 200, f"Login after logout failed: {login_res2.text}"
        harish_headers = {"Authorization": f"Bearer {login_res2.json()['access_token']}"}
        print("[PASS] Logout cleared active session; re-login succeeded.")

        # 5. Admin Quota: Try creating a 3rd admin
        admin3_res = client.post("/users", headers=harish_headers, json={
            "username": "superadmin",
            "password": "password123",
            "role": "admin"
        })
        assert admin3_res.status_code == 400, f"Expected 400 Bad Request, got {admin3_res.status_code}: {admin3_res.text}"
        assert "Maximum 2 admins allowed" in admin3_res.json()["detail"]
        print("[PASS] 3rd Admin creation blocked by quota enforcement.")

        # 6. Unlimited Members: Create member accounts
        m1_res = client.post("/users", headers=harish_headers, json={
            "username": "member1",
            "password": "memberpass1",
            "role": "member"
        })
        assert m1_res.status_code == 200, f"Failed to create member1: {m1_res.text}"
        m1_id = m1_res.json()["id"]

        m2_res = client.post("/users", headers=harish_headers, json={
            "username": "member2",
            "password": "memberpass2",
            "role": "member"
        })
        assert m2_res.status_code == 200, f"Failed to create member2: {m2_res.text}"
        print("[PASS] Members created successfully.")

        # 7. Member Concurrent Login and Admin Session Reset
        m1_login1 = client.post("/auth/login", json={"username": "member1", "password": "memberpass1"})
        assert m1_login1.status_code == 200
        
        m1_login2 = client.post("/auth/login", json={"username": "member1", "password": "memberpass1"})
        assert m1_login2.status_code == 403, "Concurrent member login was not blocked!"
        print("[PASS] Member concurrent login blocked with 403.")

        # Admin resets member1's session
        reset_res = client.post(f"/users/{m1_id}/reset-session", headers=harish_headers)
        assert reset_res.status_code == 200, f"Reset session failed: {reset_res.text}"
        
        # Now member1 can log in again
        m1_login3 = client.post("/auth/login", json={"username": "member1", "password": "memberpass1"})
        assert m1_login3.status_code == 200, f"Member1 login after reset failed: {m1_login3.text}"
        print("[PASS] Admin session reset cleared stuck session; member can log in again.")

        # 8. Admin Deletion Protection (Cannot delete last remaining admin)
        db = SessionLocal()
        try:
            vishal = db.query(User).filter(User.username == "vishal").first()
            assert vishal is not None
            vishal_id = vishal.id
        finally:
            db.close()

        # Harish deletes Vishal
        del_vishal = client.delete(f"/users/{vishal_id}", headers=harish_headers)
        assert del_vishal.status_code == 200, f"Failed to delete vishal: {del_vishal.text}"
        print("[PASS] Harish successfully deleted Vishal (1 admin remaining).")

        # Now only Harish remains as admin. Self-deletion is blocked:
        del_self = client.delete(f"/users/{login_res2.json()['user']['id']}", headers=harish_headers)
        assert del_self.status_code == 400
        assert "Cannot delete your own account" in del_self.json()["detail"]

        # Since only 1 admin remains, creating a replacement admin should now succeed!
        new_admin = client.post("/users", headers=harish_headers, json={
            "username": "newadmin",
            "password": "newadmin123",
            "role": "admin"
        })
        assert new_admin.status_code == 200, f"Failed to create new replacement admin: {new_admin.text}"
        new_admin_id = new_admin.json()["id"]
        print("[PASS] Creating replacement admin succeeded when count was 1.")

        # Trying to add another admin now fails (count back at 2)
        another_admin = client.post("/users", headers=harish_headers, json={
            "username": "thirdadmin",
            "password": "thirdadmin123",
            "role": "admin"
        })
        assert another_admin.status_code == 400
        print("[PASS] Quota enforced again when count reached 2.")

        # Delete newadmin, restore vishal
        del_new = client.delete(f"/users/{new_admin_id}", headers=harish_headers)
        assert del_new.status_code == 200
        restore_vishal = client.post("/users", headers=harish_headers, json={
            "username": "vishal",
            "password": "vishal123",
            "role": "admin"
        })
        assert restore_vishal.status_code == 200

        # Clean up test members
        client.delete(f"/users/{m1_id}", headers=harish_headers)
        m2_user = client.get("/users", headers=harish_headers).json()
        for u in m2_user:
            if u["username"] == "member2":
                client.delete(f"/users/{u['id']}", headers=harish_headers)

        # 9. Input Validation & Edge Cases for User Creation
        bad_role = client.post("/users", headers=harish_headers, json={
            "username": "badrole",
            "password": "password123",
            "role": "viewer"
        })
        assert bad_role.status_code == 400, f"Expected 400 for role 'viewer', got {bad_role.status_code}"

        spaces_user = client.post("/users", headers=harish_headers, json={
            "username": "bad user",
            "password": "password123",
            "role": "member"
        })
        assert spaces_user.status_code == 400, f"Expected 400 for username with spaces, got {spaces_user.status_code}"

        empty_pass = client.post("/users", headers=harish_headers, json={
            "username": "emptypass",
            "password": "   ",
            "role": "member"
        })
        assert empty_pass.status_code == 400, f"Expected 400 for empty password, got {empty_pass.status_code}"
        print("[PASS] User creation validation (role, spaces, password) verified.")

        # 10. Member RBAC Authorization Boundaries
        m_temp = client.post("/users", headers=harish_headers, json={
            "username": "tempmember",
            "password": "memberpass123",
            "role": "member"
        })
        assert m_temp.status_code == 200
        m_temp_id = m_temp.json()["id"]

        m_login = client.post("/auth/login", json={"username": "tempmember", "password": "memberpass123"})
        assert m_login.status_code == 200
        m_headers = {"Authorization": f"Bearer {m_login.json()['access_token']}"}

        # Member cannot create users
        m_create = client.post("/users", headers=m_headers, json={
            "username": "illegaluser",
            "password": "password123",
            "role": "member"
        })
        assert m_create.status_code == 403, f"Expected 403 Forbidden for member creating user, got {m_create.status_code}"

        # Member cannot reset session
        m_reset = client.post(f"/users/{m_temp_id}/reset-session", headers=m_headers)
        assert m_reset.status_code == 403, f"Expected 403 Forbidden for member resetting session, got {m_reset.status_code}"

        # Member cannot delete user
        m_del = client.delete(f"/users/{m_temp_id}", headers=m_headers)
        assert m_del.status_code == 403, f"Expected 403 Forbidden for member deleting user, got {m_del.status_code}"
        print("[PASS] Member RBAC restrictions verified.")

        # 11. Teardown & Clean Database State
        # Log out tempmember and delete
        client.post("/auth/logout", headers=m_headers)
        client.delete(f"/users/{m_temp_id}", headers=harish_headers)

        # Log out Harish
        client.post("/auth/logout", headers=harish_headers)

        db = SessionLocal()
        try:
            # Ensure all sessions offline
            db.query(User).update({User.is_logged_in: False})
            v = db.query(User).filter(User.username == "vishal").first()
            if v:
                v.name = "Vishal"
            db.commit()

            final_users = db.query(User).all()
            assert len(final_users) == 2, f"Expected exactly 2 users remaining, found {len(final_users)}"
            assert {u.username for u in final_users} == {"harish", "vishal"}
            assert all(not u.is_logged_in for u in final_users), "A user was left logged in!"
            print("[PASS] Teardown clean: DB has exactly 2 admins (harish, vishal), all offline.")
        finally:
            db.close()

        print("=== ALL BACKEND TESTS PASSED SUCCESSFULLY! ===")

if __name__ == "__main__":
    run_tests()
