import streamlit as st
from snowflake.snowpark.context import get_active_session
import plotly.express as px
import pandas as pd

st.set_page_config(page_title="Cust360 Risk Analytics", layout="wide")

session = get_active_session()

@st.cache_data(ttl=300)
def q(sql):
    return session.sql(sql).to_pandas()

DB = "CUST360_NORTHBRIDGE_DATABASE"
G  = f"{DB}.GOLD"

st.title("Risk Analytics")
st.caption("NorthBridge Financial — Cust360 Gold Layer")

kpi = q(f"""
SELECT
  COUNT(*)                                                  AS TOTAL_CUST,
  SUM(CASE WHEN RISK_RATING='High' THEN 1 ELSE 0 END)      AS HIGH_RISK,
  ROUND(AVG(CREDIT_SCORE))                                  AS AVG_SCORE,
  ROUND(AVG(AML_RISK_SCORE),1)                              AS AVG_AML,
  SUM(CASE WHEN PEP_STATUS='PEP' THEN 1 ELSE 0 END)        AS PEP_CNT,
  SUM(CASE WHEN PEP_STATUS='Former PEP' THEN 1 ELSE 0 END) AS FMRPEP_CNT
FROM {G}.CUST360_DIM_CUSTOMER
""")
r = kpi.iloc[0]
c1,c2,c3,c4,c5 = st.columns(5)
c1.metric("Customers", f"{int(r.TOTAL_CUST):,}")
c2.metric("High Risk", f"{int(r.HIGH_RISK):,}", delta=f"{r.HIGH_RISK/r.TOTAL_CUST*100:.1f}%", delta_color="inverse")
c3.metric("Avg Credit Score", int(r.AVG_SCORE))
c4.metric("Avg AML Score", r.AVG_AML)
c5.metric("PEP / Former PEP", f"{int(r.PEP_CNT):,} / {int(r.FMRPEP_CNT):,}")

st.divider()

col1, col2 = st.columns(2)

with col1:
    st.subheader("Risk Rating Distribution")
    risk = q(f"SELECT RISK_RATING, COUNT(*) AS CNT FROM {G}.CUST360_DIM_CUSTOMER GROUP BY 1 ORDER BY CNT DESC")
    colors = {"High": "#EF4444", "Medium": "#F59E0B", "Low": "#22C55E"}
    fig = px.pie(risk, names="RISK_RATING", values="CNT", color="RISK_RATING",
                 color_discrete_map=colors, hole=0.45)
    fig.update_layout(margin=dict(t=10,b=10,l=10,r=10), height=320)
    st.plotly_chart(fig, use_container_width=True)

with col2:
    st.subheader("Credit Score Distribution")
    cs = q(f"""
    SELECT FLOOR(CREDIT_SCORE/50)*50 AS BUCKET, COUNT(*) AS CNT
    FROM {G}.CUST360_DIM_CUSTOMER GROUP BY 1 ORDER BY 1
    """)
    cs["LABEL"] = cs.BUCKET.astype(int).astype(str) + "-" + (cs.BUCKET.astype(int)+49).astype(str)
    fig2 = px.bar(cs, x="LABEL", y="CNT", color_discrete_sequence=["#3B82F6"])
    fig2.update_layout(xaxis_title="Score Range", yaxis_title="Customers",
                       margin=dict(t=10,b=10,l=10,r=10), height=320)
    st.plotly_chart(fig2, use_container_width=True)

st.divider()

col3, col4 = st.columns(2)

with col3:
    st.subheader("Loan Portfolio by Status")
    loans = q(f"""
    SELECT LOAN_STATUS AS "Status", COUNT(*) AS "Loans",
           ROUND(SUM(OUTSTANDING_BALANCE)/1e9,2) AS "Outstanding ($B)",
           SUM(MISSED_PAYMENTS) AS "Missed Payments"
    FROM {G}.CUST360_FACT_LOANS GROUP BY 1 ORDER BY "Outstanding ($B)" DESC
    """)
    st.dataframe(loans, use_container_width=True)
    fig3 = px.bar(loans[loans["Outstanding ($B)"] > 0], x="Status", y="Outstanding ($B)",
                  color="Status",
                  color_discrete_map={"Active":"#3B82F6","Restructured":"#F59E0B",
                                      "Defaulted":"#EF4444","Delinquent":"#F97316"})
    fig3.update_layout(yaxis_title="Outstanding ($B)", showlegend=False,
                       margin=dict(t=10,b=10,l=10,r=10), height=300)
    st.plotly_chart(fig3, use_container_width=True)

with col4:
    st.subheader("Fraud Flags")
    fraud = q(f"""
    SELECT COALESCE(FRAUD_FLAG_REASON, 'Unspecified') AS "Reason",
           COUNT(*) AS "Flags", ROUND(SUM(AMOUNT)/1e6,1) AS "Amount ($M)"
    FROM {G}.CUST360_FACT_TRANSACTIONS
    WHERE FRAUD_IS_FLAGGED = TRUE GROUP BY 1 ORDER BY "Flags" DESC
    """)
    fig4 = px.bar(fraud, x="Flags", y="Reason", orientation="h",
                  color_discrete_sequence=["#EF4444"], text="Flags")
    fig4.update_layout(yaxis_title="", xaxis_title="Flagged Transactions",
                       margin=dict(t=10,b=10,l=10,r=10), height=300)
    st.plotly_chart(fig4, use_container_width=True)
    st.dataframe(fraud, use_container_width=True)

st.divider()

st.subheader("Top 20 High-Risk Customers by Exposure")
top = q(f"""
SELECT c.CUSTOMER_ID AS "Customer ID", c.FULL_NAME AS "Name", c.CREDIT_SCORE AS "Credit Score",
       ROUND(c.AML_RISK_SCORE,1) AS "AML Score", c.PEP_STATUS AS "PEP Status",
       COUNT(l.LOAN_ID) AS "Loans",
       ROUND(SUM(l.OUTSTANDING_BALANCE)/1e6,2) AS "Outstanding ($M)",
       SUM(l.MISSED_PAYMENTS) AS "Missed"
FROM {G}.CUST360_DIM_CUSTOMER c
JOIN {G}.CUST360_FACT_LOANS l ON c.CUSTOMER_ID = l.CUSTOMER_ID
WHERE c.RISK_RATING = 'High'
GROUP BY 1,2,3,4,5
ORDER BY "Outstanding ($M)" DESC
LIMIT 20
""")
st.dataframe(top, use_container_width=True)
